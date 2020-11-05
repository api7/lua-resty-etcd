
use Test::Nginx::Socket::Lua;

log_level('warn');
no_long_string();
repeat_each(2);

my $enable_tls = $ENV{ETCD_ENABLE_TLS};
if ($enable_tls eq "TRUE") {
    plan(skip_all => "skip test cases when TLS is enabled");
} else {
    plan 'no_plan';
}

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

=== TEST 1: cluster(one etcd instance) set + delete + get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                http_host = {
                    "http://127.0.0.1:2379",
                    "http://127.0.0.1:2379",
                    "http://127.0.0.1:2379",
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


=== TEST 2: cluster set + delete + get + auth
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                http_host = {
                    "http://127.0.0.1:12379", 
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'root',
                password = 'abc123',
            })
            check_res(etcd, err)

            local res, err = etcd:set("/test", {a = "abc"})
            check_res(res, err)

            local res, err = etcd:get("/test")
            check_res(res, err)

            ngx.sleep(1)

            res, err = etcd:delete("/test")
            check_res(res, err)

            ngx.sleep(1)

            local data, err = etcd:get("/test")
            check_res(data, err, nil, "Key not found")

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
            check_res(data, err, nil, "The request requires user authentication")

            ngx.say("all done")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked error msg as expect: Key not found
err: insufficient credentials code: 401
