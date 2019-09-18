use Test::Nginx::Socket::Lua 'no_plan';

log_level('info');
no_long_string();
repeat_each(2);

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    init_by_lua_block {
        local cjson = require("cjson.safe")

        function check_res(data, err, val, err_msg)
            if err then
                ngx.say("err: ", err)
                ngx.exit(200)
            end

            if val then
                if val ~= data.body.kvs[1].value then
                    ngx.say("failed to check value, got:", data.body.kvs[1].value,
                            ", expect: ", val)
                    ngx.exit(200)
                else
                    ngx.say("checked val as expect: ", val)
                end
            end

            if err_msg then
                if err_msg ~= data.body.message then
                    ngx.say("failed to check error msg, got:",
                            data.body.message, ", expect: ", val)
                    ngx.exit(200)
                else
                    ngx.say("checked error msg as expect: ", err_msg)
                end
            end
        end
    }
_EOC_

run_tests();

__DATA__


=== TEST 1: set(key, val, ttl)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcdv3" .new()
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            local data, err = etcd:get("/test")
            check_res(data, err, "abc")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked val as expect: abc


=== TEST 2: watch(key)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcdv3" .new()
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            ngx.timer.at(1, function ()
                etcd:set("/test", "bcd")
            end)

            local cur_time = ngx.now()
            local res, err = etcd:watch("/test", 1.5)

        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
--- timeout: 5
--- ONLY
