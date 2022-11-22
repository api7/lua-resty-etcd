use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);

my $enable_tls = $ENV{ETCD_ENABLE_MTLS};
if (defined($enable_tls) && $enable_tls eq "TRUE") {
    plan 'no_plan';
} else {
    plan(skip_all => "etcd is not capable for mTLS connection");
}

my $main_config = <<'_EOC_';
    thread_pool grpc-client-nginx-module threads=1;
_EOC_

my $http_config = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/share/lua/5.1/?.lua;;';
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

        function new_etcd(ssl_verify, ssl_cert_path, ssl_key_path, trusted_ca)
            return require "resty.etcd" .new({
                protocol = "v3",
                api_prefix = "/v3",
                http_host = {
                    "https://127.0.0.1:12379",
                },
                use_grpc = true,
                ssl_verify = ssl_verify,
                ssl_cert_path = ssl_cert_path or "t/certs/mtls_client.crt",
                ssl_key_path = ssl_key_path or "t/certs/mtls_client.key",
                trusted_ca = trusted_ca,
            })
        end
    }
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->http_config) {
        $block->set_value("http_config", $http_config);
    }

    if (!$block->main_config) {
        $block->set_value("main_config", $main_config);
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests();

__DATA__

=== TEST 1: TLS no verify
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = new_etcd(false)
            check_res(etcd, err)

            local res, err = etcd:set("/test", { a='abc'})
            check_res(res, err)
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: TLS verify
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = new_etcd(true)
            check_res(etcd, err)

            local res, err = etcd:set("/test", { a='abc'})
            check_res(res, err)
            ngx.say("done")
        }
    }
--- response_body_like eval
qr/cannot validate certificate/



=== TEST 3: bad client certificate
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = new_etcd(false, "t/certs/etcd.pem", "t/certs/etcd.key")
            check_res(etcd, err)

            local res, err = etcd:set("/test", { a='abc'})
            check_res(res, err)
            ngx.say("done")
        }
    }
--- response_body_like eval
qr/bad certificate/
