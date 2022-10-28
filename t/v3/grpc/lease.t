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

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    init_by_lua_block {
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

=== TEST 1: lease grant, and wait for expiring
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd".new({protocol = "v3", use_grpc = true})
            check_res(etcd, err)

            local res, err = etcd:grant(2)
            check_res(res, err)

            local data, err = etcd:set("/test", "abc", {prev_kv = true, lease = res.body.ID})
            check_res(data, err)

            local data, err = etcd:get("/test")
            check_res(data, err, "abc")

            ngx.sleep(1)
            local data, err = etcd:get("/test")
            check_res(data, err, "abc")

            ngx.sleep(1.5)  -- till lease expired
            local data, err = etcd:get("/test")
            if data.body.kvs == nil then
                ngx.say("key expired as expect")
            end
        }
    }
--- response_body
checked val as expect: abc
checked val as expect: abc
key expired as expect



=== TEST 2: lease grant and revoke
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd".new({protocol = "v3", use_grpc = true})
            check_res(etcd, err)

            local res, err = etcd:grant(2)
            check_res(res, err)

            local data, err = etcd:set("/test1", "abc", {prev_kv = true, lease = res.body.ID})
            check_res(data, err)

            local data, err = etcd:set("/test2", "bcd", {prev_kv = true, lease = res.body.ID})
            check_res(data, err)

            local data, err = etcd:get("/test1")
            check_res(data, err, "abc")

            local data, err = etcd:get("/test2")
            check_res(data, err, "bcd")

            local data, err = etcd:revoke(res.body.ID)
            check_res(data, err)

            local data1, err1 = etcd:get("/test1")
            local data2, err2 = etcd:get("/test2")
            if data1.body.kvs == nil and data2.body.kvs == nil then
                ngx.say("deleted key as expect")
            else
                ngx.say("failed to delete key")
                ngx.exit(200)
            end
        }
    }
--- response_body
checked val as expect: abc
checked val as expect: bcd
deleted key as expect



=== TEST 3: lease grant and keealive
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd".new({protocol = "v3", use_grpc = true})
            check_res(etcd, err)

            local res, err = etcd:grant(2, 123)
            check_res(res, err)

            local res, err = etcd:grant(2, 456)
            check_res(res, err)

            local data, err = etcd:set("/test1", "abc", {prev_kv = true, lease = 123})
            check_res(data, err)

            local data, err = etcd:set("/test2", "bcd", {prev_kv = true, lease = 456})
            check_res(data, err)

            local data, err = etcd:get("/test1")
            check_res(data, err, "abc")

            local data, err = etcd:get("/test2")
            check_res(data, err, "bcd")

            local data, err = etcd:timetolive(123, true)
            check_res(data, err)
            if data.body.keys then
                if data.body.keys[1] ~= "/test1" then
                    ngx.say("lease attached keys are not as expected: ", data.body.keys)
                end
            end

            ngx.sleep(1)
            local data, err = etcd:keepalive(123)
            check_res(data, err)

            ngx.sleep(1.5)

            local data, err = etcd:get("/test1")
            if data.body.kvs == nil then
                ngx.say("Keepalive failed")
            end

            local data, err = etcd:get("/test2")
            if data.body.kvs ~= nil then
                ngx.say("Wrong lease got keepalived")
            end

            local data, err = etcd:revoke(123)
            check_res(data, err)

            ngx.say("all done")
        }
    }
--- response_body
checked val as expect: abc
checked val as expect: bcd
all done



=== TEST 4: lease grant, leases(), and wait for expiring
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd".new({protocol = "v3", use_grpc = true})
            check_res(etcd, err)

            local res, err = etcd:grant(2)
            check_res(res, err)

            local data, err = etcd:leases()
            if data.body.leases[1].ID ~= res.body.ID then
                ngx.say("leases not working")
                ngx.say("result: ", require("cjson").encode(data.body))
            end

            local data, err = etcd:set("/test", "abc", {prev_kv = true, lease = res.body.ID})
            check_res(data, err)

            local data, err = etcd:get("/test")
            check_res(data, err, "abc")

            ngx.sleep(1)
            local data, err = etcd:get("/test")
            check_res(data, err, "abc")

            ngx.sleep(1.5)  -- till lease expired
            local data, err = etcd:get("/test")
            if data.body.kvs == nil then
                ngx.say("key expired as expect")
            end
        }
    }
--- response_body
checked val as expect: abc
checked val as expect: abc
key expired as expect
