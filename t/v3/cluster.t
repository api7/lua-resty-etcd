use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);

my $etcd_version = `etcd --version`;
if ($etcd_version =~ /^etcd Version: 2/ || $etcd_version =~ /^etcd Version: 3.1./) {
    plan(skip_all => "etcd is too old, skip v3 protocol");
} else {
    plan 'no_plan';
}

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    init_by_lua_block {
        local cjson = require("cjson.safe")

        function check_res(data, err, val, status)
            if err then
                ngx.say("err: ", err)
                ngx.exit(200)
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

=== TEST 1: cluster set + delete + get + auth
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:12379", 
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'root',
                password = 'abc123',
            })
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            local res, err = etcd:get("/test")
            check_res(res, err, "abc")

            ngx.sleep(1)

            res, err = etcd:delete("/test")
            check_res(res, err)

            ngx.sleep(1)

            local data, err = etcd:get("/test")
            assert(not data.body.kvs)

            etcd, err = require "resty.etcd" .new({
                http_host = {
                    "http://127.0.0.1:12379", 
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'wrong_user_name',
                password = 'wrong_password',
            })
            data, err = etcd:get("/test")
            check_res(data, err)

            ngx.say("all done")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked val as expect: abc
err: authenticate refresh token fail
all done
