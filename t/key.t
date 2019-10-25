use Test::Nginx::Socket::Lua 'no_plan';

log_level('warn');
no_long_string();
repeat_each(2);

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    init_by_lua_block {
        function check_res(data, err, val, err_msg)
            if err then
                ngx.say("err: ", err)
                ngx.exit(200)
            end

            if val then
                if val ~= data.body.node.value then
                    ngx.say("failed to check value, got:", data.body.node.value,
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

=== TEST 1: invalid arguments
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new("a")
            ngx.say("res: ", res, " err: ", err)

            etcd, err = require "resty.etcd" .new({timeout=1.01})
            ngx.say("res: ", res, " err: ", err)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
res: nil err: opts must be table
res: nil err: opts.timeout must be unsigned integer



=== TEST 2: set(key, val)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
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



=== TEST 3: set(key, val, ttl)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc", 1)
            check_res(res, err)

            local data, err = etcd:get("/test")
            check_res(data, err, "abc")

            ngx.sleep(2)

            data, err = etcd:get("/test")
            check_res(data, err, nil, "Key not found")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked val as expect: abc
checked error msg as expect: Key not found



=== TEST 4: set + delete + get + delete + get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            res, err = etcd:delete("/test", "bcd")
            check_res(res, err, nil, "Compare failed")

            res, err = etcd:get("/test")
            check_res(res, err, "abc")

            etcd:delete("/test", "abc")

            res, err = etcd:get("/test")
            check_res(res, err, nil, "Key not found")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked error msg as expect: Compare failed
checked val as expect: abc
checked error msg as expect: Key not found



=== TEST 5: setnx(key, val)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            res, err = etcd:setnx("/test", "def")
            check_res(res, err, nil, "Key already exists")

            etcd:delete("/test")

            res, err = etcd:setnx("/test", "def")
            check_res(res, err, "def")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked error msg as expect: Key already exists
checked val as expect: def



=== TEST 6: setx(key, val)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            etcd:delete("/test")

            local res, err = etcd:setx("/test", "abc")
            check_res(res, err, nil, "Key not found")

            res, err = etcd:set("/test", "def")
            check_res(res, err, "def")

            res, err = etcd:setx("/test", "abc")
            check_res(res, err, "abc")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked error msg as expect: Key not found
checked val as expect: def
checked val as expect: abc



=== TEST 7: wait(key)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err, "abc")

            local cur_time = ngx.now()
            local res2, err = etcd:wait("/test", res.body.node.modifiedIndex + 1, 1)
            ngx.say("err: ", err, ", more than 1sec: ", ngx.now() - cur_time > 1)

            ngx.timer.at(1.5, function ()
                etcd:set("/test", "bcd")
            end)

            cur_time = ngx.now()
            res, err = etcd:wait("/test", res.body.node.modifiedIndex + 1, 3)
            check_res(res, err, "bcd")
            ngx.say("wait more than 1sec: ", ngx.now() - cur_time > 1)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked val as expect: abc
err: timeout, more than 1sec: true
checked val as expect: bcd
wait more than 1sec: true
--- timeout: 5



=== TEST 8: set(key, val), val is a Lua table
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:set("/test", {a = "abc"})
            check_res(res, err)

            local data, err = etcd:get("/test")
            check_res(data, err)

            assert(data.body.node.value.a == "abc")
            ngx.say("all done")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
all done



=== TEST 9: set + delete + get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:set("/test", {a = "abc"})
            check_res(res, err)

            res, err = etcd:delete("/test")
            check_res(res, err)

            local data, err = etcd:get("/test")
            check_res(data, err, nil, "Key not found")

            -- ngx.log(ngx.ERR, "data: ", require("cjson").encode(data.body))
            ngx.say("all done")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked error msg as expect: Key not found
all done



=== TEST 10: invalid cluster arguments
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                host = true
            })
            ngx.say("res: ", res, " err: ", err)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
res: nil err: opts.host must be string or table



=== TEST 11: invalid basicauth arguments
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                user = true,
                password = "pwd",
            })
            ngx.print("res: ", res, " err: ", err)

            ngx.print("\n")

            local etcd, err = require "resty.etcd" .new({
                user = "user",
                password = true,
            })
            ngx.print("res: ", res, " err: ", err)

            ngx.print("\n")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
res: nil err: opts.user must be string or ignore
res: nil err: opts.password must be string or ignore
--- timeout: 5



=== TEST 12: cluster set + delete + get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                host = {
                    "http://127.0.0.1:12379", 
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                }
            })
            check_res(etcd, err)

            local res, err = etcd:set("/test", {a = "abc"})
            check_res(res, err)

            ngx.sleep(1)

            res, err = etcd:delete("/test")
            check_res(res, err)

            ngx.sleep(1)

            local data, err = etcd:get("/test")
            check_res(data, err, nil, "Key not found")

            ngx.say("all done")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked error msg as expect: Key not found
all done
