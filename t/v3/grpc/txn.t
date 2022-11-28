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

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->main_config) {
        $block->set_value("main_config", "thread_pool grpc-client-nginx-module threads=1;");
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }
});

run_tests();

__DATA__

=== TEST 1: txn("EQUAL") and get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3", use_grpc = true})
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
--- response_body
checked val as expect: abc
checked val as expect: ddd



=== TEST 2: txn(not "EQUAL") and get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3", use_grpc = true})
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
--- response_body
checked val as expect: abc
checked val as expect: abc



=== TEST 3: setnx(key, val)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3", use_grpc = true})
            check_res(etcd, err)

            local res, err = etcd:delete("/setnx")
            check_res(res, err)

            local res, err = etcd:setnx("/setnx", "aaa")
            check_res(res, err, nil, 200)

            local res, err = etcd:setnx("/setnx", "bbb")
            check_res(res, err, nil, 200)

            local data, err = etcd:get("/setnx")
            check_res(data, err, "aaa", 200)
        }
    }
--- response_body
checked val as expect: aaa



=== TEST 4: txn with table
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local cjson = require("cjson.safe")
            local function check_res(data, err, val, status)
                if err then
                    ngx.say("err: ", err)
                    ngx.exit(200)
                end

                if val then
                    if data.body.kvs==nil then
                        ngx.exit(404)
                    end
                    if data.body.kvs and val ~= cjson.encode(data.body.kvs[1].value) then
                        ngx.say("failed to check value")
                        ngx.log(ngx.ERR, "failed to check value, got: ",
                                cjson.encode(data.body.kvs[1].value),
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

            local etcd, err = require "resty.etcd" .new({protocol = "v3", use_grpc = true})
            check_res(etcd, err)

            local res, err = etcd:set("/test", {k = "abc"})
            check_res(res, err)

            local data, err = etcd:get("/test")
            check_res(data, err,  '{"k":"abc"}')

            local data, err = etcd:txn(
                {{key = "/test", result = "EQUAL", value = {k = "abc"}, target = "VALUE"}},
                {{requestPut = {key = "/test", value = {k = "ddd"}}}}
            )
            check_res(data, err)

            local data, err = etcd:get("/test")
            check_res(data, err, '{"k":"ddd"}')
        }
    }
--- response_body
checked val as expect: {"k":"abc"}
checked val as expect: {"k":"ddd"}
