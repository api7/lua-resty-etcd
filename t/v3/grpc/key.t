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
        local cjson = require("cjson.safe")

        function check_res(data, err, val, status)
            if err then
                ngx.say("err: ", err)
                ngx.exit(200)
            end

            if val then
                if data and data.body.kvs==nil then
                    ngx.exit(400)
                end
                if data and data.body.kvs and #data.body.kvs ~= 0 and
                  ((#val == 0) or (val ~= data.body.kvs[1].value)) then
                    ngx.say("failed to check value")
                    ngx.log(ngx.ERR, "failed to check value, got: ", data.body.kvs[1].value,
                            ", expect: ", val)
                    ngx.exit(200)
                else
                    ngx.say("checked val as expect: ", #val == 0 and "[]" or val)
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

=== TEST 1: set(key, val) and get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3", use_grpc = true})
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc", {prev_kv = true})
            check_res(res, err)

            local data, err = etcd:get("/test")
            check_res(data, err, "abc")

            local data, err = etcd:get("")
            check_res(data, nil, err)

            local data, err = etcd:set("")
            check_res(data, nil, err)
        }
    }
--- response_body
checked val as expect: abc
checked val as expect: failed to call: rpc error: code = InvalidArgument desc = etcdserver: key is not provided
checked val as expect: failed to call: rpc error: code = InvalidArgument desc = etcdserver: key is not provided



=== TEST 2: readdir(key)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local tab_nkeys     = require "table.nkeys"
            local etcd, err = require "resty.etcd" .new({protocol = "v3", use_grpc = true})
            check_res(etcd, err)

            local res, err = etcd:set("/dir", "abc")
            check_res(res, err)

            local res, err = etcd:set("/dir/a", "abca")
            check_res(res, err)

            local data, err = etcd:readdir("/dir")
            if tab_nkeys(data.body.kvs) == 2 then
                ngx.say("ok")
                ngx.exit(200)
            else
                ngx.say("failed")
            end

        }
    }
--- response_body
ok



=== TEST 3: set/del/get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3", use_grpc = true})
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc", {prev_kv = true})
            check_res(res, err)

            local data, err = etcd:get("/test")
            check_res(data, err, "abc")

            local data, err = etcd:delete("/test")
            assert(data.body.deleted == 1)

            local data, err = etcd:get("/test")
            check_res(data, nil, {})

            local data, err = etcd:delete("/test")
            assert(data.body.deleted == 0)
            local data, err = etcd:get("/test")
            check_res(data, nil, {})
        }
    }
--- response_body
checked val as expect: abc
checked val as expect: []
checked val as expect: []
