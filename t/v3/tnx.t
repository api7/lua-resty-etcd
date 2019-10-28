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
                    ngx.log(ngx.ERR, "failed to check value, got: ",data.body.kvs[1].value,
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

=== TEST 1: txn("EQUAL") and get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            local data, err = etcd:get("/test")
            check_res(data, err, "abc")

            local data, err = etcd:txn(
                {{key = "/test", result = "EQUAL", value = "abc", target = "VALUE"}},
                {{requestPut = {key = "/test", value = "ddd"}}}
            )
            check_res(data, err)

            local data, err = etcd:get("/test")
            check_res(data, err, "ddd")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked val as expect: abc
checked val as expect: ddd



=== TEST 2: txn(not "EQUAL") and get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            local data, err = etcd:get("/test")
            check_res(data, err, "abc")

            local data, err = etcd:txn(
                {{key = "/test", result = "EQUAL", value = "not equal", target = "VALUE"}},
                {{requestPut = {key = "/test", value = "ddd"}}}
            )
            check_res(data, err)

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
checked val as expect: abc
