use Test::Nginx::Socket::Lua 'no_plan';

log_level('warn');
no_long_string();
repeat_each(2);

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    init_by_lua_block {
        local cjson = require("cjson.safe")

        function check_res(data, err, val, status)
            if err then
                ngx.say("err: ", err)
            end

            if val then
                if data and data.body.kvs==nil then
                    ngx.exit(404)
                end
                if data and data.body.kvs and val ~= data.body.kvs[1].value then
                    ngx.say("failed to check value")
                    ngx.log(ngx.ERR, "failed to check value, got: ", data.body.kvs[1].value,
                            ", expect: ", val)
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

=== TEST 1: raw string serializer
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local cjson = require("cjson.safe")

            local etcd, err = require("resty.etcd").new({
                protocol = "v3",
                serializer = "raw"
            })
            check_res(etcd, err)

            local res
            res, err = etcd:set("/dir/v3/a", 111)
            check_res(res, err)

            res, err = etcd:set("/dir/v3/b", '"foo"')
            check_res(res, err)

            res, err = etcd:get("/dir/v3/b")
            check_res(res, err, '"foo"')
            
            local s = cjson.encode({a = 1})
            res, err = etcd:setx("/dir/v3/c", s)
            check_res(res, err, nil, 200)

            res, err = etcd:get("/dir/v3/c")
            check_res(res, err, s, 200)

            res, err = etcd:setnx("/dir/v3/d", "")
            check_res(res, err, nil, 200)

            res, err = etcd:get("/dir/v3/d")
            check_res(res, err, "", 200)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
err: unsupported type for number
checked val as expect: "foo"
checked val as expect: {"a":1}
checked val as expect: 


=== TEST 2: json serializer
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local cjson = require("cjson.safe")

            local etcd, err = require("resty.etcd").new({
                protocol = "v3",
                serializer = "json"
            })
            check_res(etcd, err)

            local res
            res, err = etcd:set("/dir/v3/a", 111)
            check_res(res, err)

            res, err = etcd:get("/dir/v3/a")
            check_res(res, err, 111)

            res, err = etcd:set("/dir/v3/b", '"foo"')
            check_res(res, err)

            res, err = etcd:get("/dir/v3/b")
            check_res(res, err, '"foo"')
            
            local s = cjson.encode({a = 1})
            res, err = etcd:setx("/dir/v3/c", s)
            check_res(res, err, nil, 200)

            res, err = etcd:get("/dir/v3/c")
            check_res(res, err, s, 200)

            res, err = etcd:setnx("/dir/v3/d", "")
            check_res(res, err, nil, 200)

            res, err = etcd:get("/dir/v3/d")
            check_res(res, err, "", 200)
        }
    }
--- request
GET /t
--- error_log
failed to check value, got: nil, expect:
--- response_body
checked val as expect: 111
checked val as expect: "foo"
checked val as expect: {"a":1}
failed to check value
