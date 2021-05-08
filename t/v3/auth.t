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
uri: http://127.0.0.1:12379/v3/kv/put, timeout: 3
uri: http://127.0.0.1:12379/v3/auth/authenticate, timeout: 3
uri: http://127.0.0.1:12379/v3/kv/put, timeout: 3
uri: http://127.0.0.1:12379/v3/kv/put, timeout: 3
uri: http://127.0.0.1:12379/v3/kv/deleterange, timeout: 3
uri: http://127.0.0.1:12379/v3/kv/deleterange, timeout: 3
uri: http://127.0.0.1:12379/v3/kv/deleterange, timeout: 3



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
uri: http://127.0.0.1:12379/v3/kv/put, timeout: 3
uri: http://127.0.0.1:12379/v3/auth/authenticate, timeout: 3
uri: http://127.0.0.1:12379/v3/kv/put, timeout: 3
uri: http://127.0.0.1:12379/v3/kv/put, timeout: 3
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
qr/(uri: .+, timeout: \d+|v3 refresh jwt last err: [^,]+|connection refused)/
--- grep_error_log_out
uri: http://127.0.0.1:1997/v3/kv/put, timeout: 3
uri: http://127.0.0.1:1997/v3/auth/authenticate, timeout: 3
uri: http://127.0.0.1:1997/v3/kv/put, timeout: 3
uri: http://127.0.0.1:1997/v3/kv/put, timeout: 3
connection refused
v3 refresh jwt last err: connection refused
connection refused
v3 refresh jwt last err: connection refused
connection refused
