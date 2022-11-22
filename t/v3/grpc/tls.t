use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);

my $enable_tls = $ENV{ETCD_ENABLE_TLS};
if (defined($enable_tls) && $enable_tls eq "TRUE") {
    plan 'no_plan';
} else {
    plan(skip_all => "etcd is not capable for TLS connection");
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

=== TEST 1: TLS no verify
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "https://127.0.0.1:12379",
                    "https://127.0.0.1:22379",
                    "https://127.0.0.1:32379",
                },
                ssl_verify = false,
                use_grpc = true,
            })
            check_res(etcd, err)

            local res, err = etcd:set("/test", { a='abc'})
            check_res(res, err)
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: TLS verify
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "https://127.0.0.1:12379",
                    "https://127.0.0.1:22379",
                    "https://127.0.0.1:32379",
                },
                use_grpc = true,
            })
            check_res(etcd, err)

            local res, err = etcd:set("/test", { a='abc'})
            check_res(res, err)
            ngx.say("done")
        }
    }
--- response_body eval
qr/authentication handshake failed/
