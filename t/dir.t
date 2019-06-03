use Test::Nginx::Socket::Lua 'no_plan';

log_level('warn');
no_long_string();
repeat_each(2);

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    init_by_lua_block {
        function check_res(data, err, val, err_msg, is_dir)
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

            if is_dir then
                if not data.body.node.dir then
                    ngx.say("failed to check dir, got normal file:",
                            data.body.node.dir)
                    ngx.exit(200)
                else
                    ngx.say("checked [", data.body.node.key, "] is dir.")
                end
            end
        end
    }
_EOC_

run_tests();

__DATA__

=== TEST 1: rmdir + mkdir + mkdir
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            res, err = etcd:readdir("/dir")
            check_res(res, err, nil, "Key not found")

            res, err = etcd:mkdir("/dir")
            check_res(res, err, nil, nil, true)

            res, err = etcd:mkdir("/dir")
            check_res(res, err, nil, "Not a file")

            res, err = etcd:rmdir("/dir", true)
            check_res(res, err)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked error msg as expect: Key not found
checked [/dir] is dir.
checked error msg as expect: Not a file



=== TEST 2: rmdir + mkdirnx + mkdirnx
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            res, err = etcd:mkdirnx("/dir", 1)
            check_res(res, err, nil, nil, true)

            res, err = etcd:mkdirnx("/dir")
            check_res(res, err, nil, "Key already exists")

            ngx.sleep(2)

            res, err = etcd:mkdirnx("/dir")
            check_res(res, err, nil, nil, true)

            res, err = etcd:rmdir("/dir", true)
            check_res(res, err)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked [/dir] is dir.
checked error msg as expect: Key already exists
checked [/dir] is dir.



=== TEST 3: readdir one item
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            res, err = etcd:mkdirnx("/dir")
            check_res(res, err, nil, nil, true)

            res, err = etcd:set("/dir/a", "a")
            check_res(res, err, "a")

            res, err = etcd:readdir("/dir")
            check_res(res, err)

            local nodes = res.body.node.nodes
            assert(nodes[1].value == 'a')
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked [/dir] is dir.
checked val as expect: a



=== TEST 4: readdir: two items
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            res, err = etcd:mkdirnx("/dir")
            check_res(res, err, nil, nil, true)

            res, err = etcd:set("/dir/a", "a")
            check_res(res, err, "a")
            res, err = etcd:set("/dir/b", "b")
            check_res(res, err, "b")

            res, err = etcd:readdir("/dir")
            check_res(res, err)

            local nodes = res.body.node.nodes
            assert(nodes[1].value == 'a' or nodes[1].value == 'b')
            assert(nodes[2].value == 'a' or nodes[2].value == 'b')
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked [/dir] is dir.
checked val as expect: a
checked val as expect: b



=== TEST 5: waitdir
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            res, err = etcd:mkdir("/dir")
            check_res(res, err, nil, nil, true)

            local cur_time = ngx.now()
            local res2, err = etcd:wait("/dir", res.body.node.modifiedIndex + 1, 1)
            ngx.say("err: ", err, ", more than 1sec: ", ngx.now() - cur_time > 1)

            ngx.timer.at(1, function ()
                etcd:set("/dir/a", "a")
            end)

            cur_time = ngx.now()
            res, err = etcd:waitdir("/dir", res.body.node.modifiedIndex + 1, 5)

            check_res(res, err, "a")
            ngx.say("wait more than 1sec: ", ngx.now() - cur_time > 1)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked [/dir] is dir.
err: timeout, more than 1sec: true
checked val as expect: a
wait more than 1sec: true



=== TEST 6: push
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            res, err = etcd:mkdir("/dir")
            check_res(res, err, nil, nil, true)

            res, err = etcd:push("/dir", "a")
            check_res(res, err, "a")

            res, err = etcd:push("/dir", "b")
            check_res(res, err, "b")

            res, err = etcd:readdir("/dir")
            check_res(res, err)
            local t = {a = 1, b = 1}
            t[res.body.node.nodes[1].value] = nil
            t[res.body.node.nodes[2].value] = nil

            assert(t.a == nil)
            assert(t.b == nil)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked [/dir] is dir.
checked val as expect: a
checked val as expect: b



=== TEST 7: dir + json_val
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            res, err = etcd:mkdir("/dir")
            check_res(res, err, nil, nil, true)

            local json_val = require("cjson").encode({a = 1, b = 2})
            res, err = etcd:set("/dir/a", json_val)
            check_res(res, err)

            res, err = etcd:readdir("/dir")
            check_res(res, err)

            ngx.say("item count: ", #res.body.node.nodes)
            ngx.say("item value: ", require("cjson").encode(res.body.node.nodes[1].value))

            res, err = etcd:get("/dir")
            check_res(res, err)
            ngx.say("item count: ", #res.body.node.nodes)
            ngx.say("item value: ", require("cjson").encode(res.body.node.nodes[1].value))
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked [/dir] is dir.
item count: 1
item value: "{\"a\":1,\"b\":2}"
item count: 1
item value: "{\"a\":1,\"b\":2}"



=== TEST 8: dir + lua table
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            res, err = etcd:mkdir("/dir")
            check_res(res, err, nil, nil, true)

            res, err = etcd:set("/dir/a", {a = 1, b = 2})
            check_res(res, err)

            res, err = etcd:readdir("/dir")
            check_res(res, err)

            ngx.say("item count: ", #res.body.node.nodes)
            ngx.say("item value: ", require("cjson").encode(res.body.node.nodes[1].value))

            res, err = etcd:get("/dir")
            check_res(res, err)
            ngx.say("item count: ", #res.body.node.nodes)
            ngx.say("item value: ", require("cjson").encode(res.body.node.nodes[1].value))
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked [/dir] is dir.
item count: 1
item value: {"a":1,"b":2}
item count: 1
item value: {"a":1,"b":2}



=== TEST 9: dir + set + delete + readdir
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            res, err = etcd:mkdir("/dir")
            check_res(res, err, nil, nil, true)

            res, err = etcd:set("/dir/a", {a = 1})
            check_res(res, err)

            res, err = etcd:set("/dir/b", {b = 2})
            check_res(res, err)

            res, err = etcd:delete("/dir/a")
            check_res(res, err)

            res, err = etcd:readdir("/dir")
            check_res(res, err)

            ngx.say("item count: ", #res.body.node.nodes)
            ngx.say("item value: ", require("cjson").encode(res.body.node.nodes[1].value))
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked [/dir] is dir.
item count: 1
item value: {"b":2}



=== TEST 10: dir + sub_dir + set + delete + readdir
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new()
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            res, err = etcd:mkdir("/dir")
            check_res(res, err, nil, nil, true)

            res, err = etcd:mkdir("/dir/sub_dir")
            check_res(res, err, nil, nil, true)

            res, err = etcd:set("/dir/sub_dir/a", {a = 1})
            check_res(res, err)

            res, err = etcd:readdir("/dir", true)
            check_res(res, err)

            ngx.say("item value: ", require("cjson").encode(res.body.node.nodes[1].nodes[1].value))
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked [/dir] is dir.
checked [/dir/sub_dir] is dir.
item value: {"a":1}
