use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);

my $test_dir = html_dir();
$ENV{TEST_NGINX_HTML_DIR} ||= $test_dir;

my $etcd_version = `etcd --version`;
if ($etcd_version =~ /^etcd Version: 2/ || $etcd_version =~ /^etcd Version: 3.1./) {
    plan(skip_all => "etcd is too old, skip v3 protocol");
} else {
    plan 'no_plan';
}

our $HttpConfig = <<"_EOC_";
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.1/?.lua;;';
    init_by_lua_block {
        local cjson = require("cjson.safe")

        function check_res(data, err, val, status)
            if err then
                ngx.say("err: ", err)
                ngx.exit(200)
            end

            if val then
                if data and data.body.kvs==nil then
                    ngx.exit(404)
                end
                if data and data.body.kvs and val ~= data.body.kvs[1].value then
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

    server {
        listen unix:$test_dir/lua-resty-etcd.sock;
        location / {
            access_by_lua_block {
                ngx.log(ngx.WARN, "hit with host ", ngx.var.http_host)
            }
            proxy_pass http://127.0.0.1:2379;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host \$http_host;
        }
    }
_EOC_

run_tests();

__DATA__

=== TEST 1: request over unix socket
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new({protocol = "v3", unix_socket_proxy = "unix:$TEST_NGINX_HTML_DIR/lua-resty-etcd.sock"})
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            ngx.timer.at(0.1, function ()
                etcd:set("/test", "bcd3")
            end)

            ngx.timer.at(0.2, function ()
                etcd:set("/test", "bcd4")
            end)

            local cur_time = ngx.now()
            local body_chunk_fun, err, http_cli = etcd:watch("/test", {timeout = 0.5, need_cancel = true})

            if type(http_cli) ~= "table" then
                ngx.say("need_cancel failed")
            end

            if not body_chunk_fun then
                ngx.say("failed to watch: ", err)
            end

            local chunk, err = body_chunk_fun()
            ngx.say("created: ", chunk.result.created)
            local chunk, err = body_chunk_fun()
            ngx.say("value: ", chunk.result.events[1].kv.value)

            local res, err = etcd:watchcancel(http_cli)
            if not res then
                ngx.say("failed to cancel: ", err)
            end

            local chunk, err = body_chunk_fun()
            ngx.say(err)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- grep_error_log eval
qr/hit with host 127.0.0.1/
--- grep_error_log_out
hit with host 127.0.0.1
hit with host 127.0.0.1
hit with host 127.0.0.1
--- response_body
created: true
value: bcd3
closed
ok
--- timeout: 5



=== TEST 2: request over unix socket, unix socket doesn't exist
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new({protocol = "v3", http_host = "http://127.0.0.1:2379",
                unix_socket_proxy = "unix:$TEST_NGINX_HTML_DIR/bad.sock"})
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            ngx.timer.at(0.1, function ()
                etcd:set("/test", "bcd3")
            end)

            ngx.timer.at(0.2, function ()
                etcd:set("/test", "bcd4")
            end)

            local cur_time = ngx.now()
            local body_chunk_fun, err, http_cli = etcd:watch("/test", {timeout = 0.5, need_cancel = true})

            if type(http_cli) ~= "table" then
                ngx.say("need_cancel failed")
            end

            if not body_chunk_fun then
                ngx.say("failed to watch: ", err)
            end

            local chunk, err = body_chunk_fun()
            ngx.say("created: ", chunk.result.created)
            local chunk, err = body_chunk_fun()
            ngx.say("value: ", chunk.result.events[1].kv.value)

            local res, err = etcd:watchcancel(http_cli)
            if not res then
                ngx.say("failed to cancel: ", err)
            end

            local chunk, err = body_chunk_fun()
            ngx.say(err)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- grep_error_log eval
qr/hit with host 127.0.0.1/
--- grep_error_log_out
--- response_body
created: true
value: bcd3
closed
ok
--- timeout: 5
