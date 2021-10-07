use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);

my $etcd_version = `etcd --version`;
if ($etcd_version =~ /^etcd Version: 2/ || $etcd_version =~ /^etcd Version: 3.[123]./) {
    plan(skip_all => "etcd is too old");
} else {
    my $enable_tls = $ENV{ETCD_ENABLE_TLS};
    if ((defined $enable_tls) && $enable_tls eq "TRUE") {
        plan(skip_all => "skip test cases with auth when TLS is enabled");
    } else {
        plan 'no_plan';
    }
}

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    init_by_lua_block {
        local cjson = require("cjson.safe")

        function check_res(data, err, val, status)
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return
            end

            if val then
                if data.body.kvs==nil then
                    ngx.exit(404)
                end
                if data.body.kvs and val ~= data.body.kvs[1].value then
                    ngx.say("failed to check value")
                    ngx.log(ngx.ERR, "failed to check value, got: ", data.body.kvs[1].value,
                            ", expect: ", val)
                    ngx.exit(200)
                else
                    ngx.say("checked val as expect: ", val)
                end
            end

            if status and status ~= data.status then
                ngx.exit(data.status)
            end
        end
    }
_EOC_

run_tests();

__DATA__

=== TEST 1: share same etcd auth token
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                user = 'root',
                password = 'abc123',
                timeout = 3,
                http_host = {
                    "http://127.0.0.1:12379",
                },
            })
            check_res(etcd, err)

            local t = {}
            for i = 1, 3 do
                local th = assert(ngx.thread.spawn(function(i)
                    local res, err = etcd:set("/test", { a='abc'})
                    check_res(res, err)

                    ngx.sleep(0.1)

                    res, err = etcd:delete("/test")
                    check_res(res, err)
                end))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end
            ngx.say('ok')
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
ok
--- grep_error_log eval
qr/uri: .+, timeout: \d+/
--- grep_error_log_out
uri: /kv/put, timeout: 3
uri: /auth/authenticate, timeout: 3
uri: /kv/put, timeout: 3
uri: /kv/put, timeout: 3
uri: /kv/deleterange, timeout: 3
uri: /kv/deleterange, timeout: 3
uri: /kv/deleterange, timeout: 3



=== TEST 2: share same etcd auth token, auth failed
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                user = 'root',
                password = '123',
                timeout = 3,
                http_host = {
                    "http://127.0.0.1:12379",
                },
            })
            check_res(etcd, err)

            local t = {}
            for i = 1, 3 do
                local th = assert(ngx.thread.spawn(function(i)
                    local res, err = etcd:set("/test", { a='abc'})
                    if not res then
                        ngx.log(ngx.ERR, err)
                    end
                end))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end
            ngx.say('ok')
        }
    }
--- request
GET /t
--- response_body
ok
--- grep_error_log eval
qr/(uri: .+, timeout: \d+|v3 refresh jwt last err: [^,]+|authenticate refresh token fail)/
--- grep_error_log_out
uri: /kv/put, timeout: 3
uri: /auth/authenticate, timeout: 3
uri: /kv/put, timeout: 3
uri: /kv/put, timeout: 3
authenticate refresh token fail
v3 refresh jwt last err: authenticate refresh token fail
authenticate refresh token fail
v3 refresh jwt last err: authenticate refresh token fail
authenticate refresh token fail



=== TEST 3: share same etcd auth token, failed to connect
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                user = 'root',
                password = '123',
                timeout = 3,
            })
            check_res(etcd, err)

            -- hack to inject 'connection refused' error
            etcd.endpoints = {{
                full_prefix = "http://127.0.0.1:1997/v3",
                scheme      = "http",
                host        = "127.0.0.1",
                port        = "1997",
            }}

            local t = {}
            for i = 1, 3 do
                local th = assert(ngx.thread.spawn(function(i)
                    local res, err = etcd:set("/test", { a='abc'})
                    if not res then
                        ngx.log(ngx.ERR, err)
                    end
                end))
                table.insert(t, th)
            end
            for i, th in ipairs(t) do
                ngx.thread.wait(th)
            end
            ngx.say('ok')
        }
    }
--- request
GET /t
--- response_body
ok
--- grep_error_log eval
qr/(uri: .+, timeout: \d+|has no healthy [^,]+)/
--- grep_error_log_out
uri: /kv/put, timeout: 3
uri: /auth/authenticate, timeout: 3
has no healthy etcd endpoint available
uri: /kv/put, timeout: 3
uri: /auth/authenticate, timeout: 3
has no healthy etcd endpoint available
uri: /kv/put, timeout: 3
uri: /auth/authenticate, timeout: 3
has no healthy etcd endpoint available
--- ONLY


=== TEST 4: Authorization header will not be overridden when etcd auth is enabled(request uri)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                user = 'root',
                password = 'abc123',
                timeout = 3,
                http_host = {
                    "http://127.0.0.1:12379",
                },
                extra_headers = {
                    Authorization = "bar",
                },
            })
            check_res(etcd, err)
            local res, err = etcd:set("/test", { a='abc'})
            check_res(res, err)
            ngx.say('ok')
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
ok



=== TEST 5: Authorization header will not be overridden when etcd auth is enabled(request chunk)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                user = 'root',
                password = 'abc123',
                timeout = 3,
                http_host = {
                    "http://127.0.0.1:12379",
                },
                extra_headers = {
                    Authorization = "bar",
                },
            })
            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            ngx.timer.at(0.1, function ()
                etcd:set("/test", "bcd3")
            end)

            local cur_time = ngx.now()
            local body_chunk_fun, err = etcd:watch("/test", {timeout = 0.5})
            if not body_chunk_fun then
                ngx.say("failed to watch: ", err)
            end

            local idx = 0
            while true do
                local chunk, err = body_chunk_fun()

                if not chunk then
                    if err then
                        ngx.say(err)
                    end
                    break
                end

                idx = idx + 1
                ngx.say(idx, ": ", require("cjson").encode(chunk.result))
            end
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body_like eval
qr/1:.*"created":true.*
2:.*"value":"bcd3".*
timeout/
--- timeout: 5
