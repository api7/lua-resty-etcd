use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);

my $enable_tls = $ENV{ETCD_ENABLE_MTLS};
if ($enable_tls eq "TRUE") {
    plan 'no_plan';
} else {
    plan(skip_all => "etcd is not capable for mTLS connection");
}

my $http_config = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/share/lua/5.1/?.lua;;';
    lua_ssl_trusted_certificate  ../../../t/certs/mtls_ca.crt;
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

        function new_etcd(ssl_verify, ssl_cert_path, ssl_key_path, sni)
            return require "resty.etcd" .new({
                protocol = "v3",
                api_prefix = "/v3",
                http_host = {
                    "https://127.0.0.1:12379",
                    "https://127.0.0.1:22379",
                    "https://127.0.0.1:32379",
                },
                ssl_verify = ssl_verify,
                ssl_cert_path = ssl_cert_path or "t/certs/mtls_client.crt",
                ssl_key_path = ssl_key_path or "t/certs/mtls_client.key",
                sni = sni,
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

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests();

__DATA__

=== TEST 1: without sni, use host(127.0.0.1) as sni by default
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = new_etcd(true)
            local res, err = etcd:set("/test", { a='abc'})
            if err then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
certificate host mismatch



=== TEST 2: certificate host mismatch (requesy uri)
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = new_etcd(true, nil, nil, "wrong.sni")
            local res, err = etcd:set("/test", { a='abc'})
            if err then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
certificate host mismatch



=== TEST 3: sni match server cert common name (requesy uri)
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = new_etcd(true, nil, nil, "127.0.0.1")
            local res, err = etcd:set("/test", { a='abc'})
            if err then
                ngx.say(err)
            else
                ngx.say("done")
            end
        }
    }
--- response_body
done



=== TEST 4: certificate host mismatch (requesy chunk)
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = new_etcd(true, nil, nil, "127.0.0.1")
            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            ngx.timer.at(0.1, function ()
                etcd:set("/test", "bcd3")
            end)

            local cur_time = ngx.now()
            local body_chunk_fun, err = etcd:watch("/test", {timeout = 0.5})
            if not body_chunk_fun then
                ngx.say("failed to watch: ", err)
            else
                ngx.say("done")
            end

        }
    }
--- response_body
err: certificate host mismatch



=== TEST 5: sni match server cert common name (requesy chunk)
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = new_etcd(true, nil, nil, "admin.apisix.dev")
            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            ngx.timer.at(0.1, function ()
                etcd:set("/test", "bcd3")
            end)

            local cur_time = ngx.now()
            local body_chunk_fun, err = etcd:watch("/test", {timeout = 0.5})
            if not body_chunk_fun then
                ngx.say("failed to watch: ", err)
            else
                ngx.say("done")
            end

        }
    }
--- response_body
done
