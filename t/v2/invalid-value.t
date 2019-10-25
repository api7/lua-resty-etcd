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

=== TEST 1: readdir one item
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new()
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir", true)
            check_res(res, err)

            ngx.say("first")

            res, err = etcd:mkdir("/dir")
            check_res(res, err, nil, nil, true)

            etcd.encode_json = function (val)
                return val
            end

            res, err = etcd:set("/dir/a", "{xxxxxxxx")
            check_res(res, err) -- err
            ngx.say("done set")

            res, err = etcd:readdir("/dir")
            check_res(res, err) -- error log
            ngx.say("done readdir")
        }
    }
--- request
GET /t
--- error_log
failed to json decode value of node: Expected object key string but found invalid token at character 2
--- response_body
first
checked [/dir] is dir.
err: Expected object key string but found invalid token at character 2
done set
done readdir
