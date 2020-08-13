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
                return
            end

            if val then
                if val ~= data.body.node.value then
                    ngx.say("failed to check value, got:", data.body.node.value,
                            ", expect: ", val)
                    return
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

=== TEST 1: raw string serializer
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local cjson = require("cjson.safe")

            local etcd, err = require("resty.etcd").new( {
                serializer = "raw"   
            })
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            res, err = etcd:mkdir("/dir")
            check_res(res, err, nil, nil, true)

            res, err = etcd:set("/dir/a", 111)
            check_res(res, err) -- err

            res, err = etcd:set("/dir/b", "")
            check_res(res, err, "")
            
            local s = cjson.encode({a = 1})
            res, err = etcd:set("/dir/c", s)
            check_res(res, err)

            res, err = etcd:get("/dir/c")
            check_res(res, err, s)

            res, err = etcd:readdir("/dir", true)
            check_res(res, err)
            for _, v in ipairs(res.body.node.nodes) do
                if v.value ~= "" and v.value ~= s then
                    return
                end
            end
            ngx.say("check readdir")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked [/dir] is dir.
err: unsupported type for number
checked val as expect: 
checked val as expect: {"a":1}
check readdir



=== TEST 2: json serializer
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new( {
                serializer = "json"   
            })
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            res, err = etcd:mkdir("/dir")
            check_res(res, err, nil, nil, true)

            etcd, err = require("resty.etcd").new( {
                serializer = "raw"   
            })
            check_res(etcd, err)

            res, err = etcd:set("/dir/a", "")
            check_res(res, err, "") -- success
            
            etcd, err = require("resty.etcd").new( {
                serializer = "json"   
            })
            check_res(etcd, err)

            res, err = etcd:get("/dir/a")
            check_res(res, err, "") -- error log
            ngx.say("res.body.node.value: ", res.body.node.value)
        }
    }
--- request
GET /t
--- error_log
failed to deserialize: Expected value but found T_END at character 1
--- response_body
checked [/dir] is dir.
checked val as expect: 
failed to check value, got:nil, expect: 
res.body.node.value: nil
