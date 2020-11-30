use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);

my $enable_tls = $ENV{ETCD_ENABLE_TLS};
if ($enable_tls eq "TRUE") {
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

    lua_shared_dict test_shm 8m;
    lua_shared_dict my_worker_events 8m;
    init_worker_by_lua_block {

        local we = require "resty.worker.events"
        local ok, err = we.configure({
            shm = "my_worker_events",
            interval = 0.1
        })
        if not ok then
            ngx.log(ngx.ERR, "failed to configure worker events: ", err)
            return
        end
    }
_EOC_

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
            })
            check_res(etcd, err)

            local res, err = etcd:set("/test", { a='abc'})
            check_res(res, err)
            ngx.say("done")
        }
    }
--- request
GET /t
--- no_error_log
[error]
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
            })
            check_res(etcd, err)

            local res, err = etcd:set("/test", { a='abc'})
            check_res(res, err)
            ngx.say("done")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
err: 18: self signed certificate



=== TEST 3: watch(key)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new({
                protocol = "v3",
                ssl_verify = false,
                http_host = {
                    "https://127.0.0.1:12379",
                    "https://127.0.0.1:22379",
                    "https://127.0.0.1:32379",
                }
            })

            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            ngx.timer.at(0.1, function ()
                etcd:set("/test", "bcd3")
            end)

            local cur_time = ngx.now()
            local body_chunk_fun, err = etcd:watch("/test", {timeout = 0.5})
            if not body_chunk_fun then
                ngx.say("failed to watch: ", err)
            end

            local idx = 0
            while true do
                local chunk, err = body_chunk_fun()

                if not chunk then
                    if err then
                        ngx.say(err)
                    end
                    break
                end

                idx = idx + 1
                ngx.say(idx, ": ", require("cjson").encode(chunk.result))
            end
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body_like eval
qr/1:.*"created":true.*
2:.*"value":"bcd3".*
timeout/
--- timeout: 5



=== TEST 4: enable health check success with TLS no verify
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
                cluster_healthcheck = {
                    shm_name = 'test_shm',
                    checks = {
                        active = {
                            type = "https",
                            https_verify_certificate = false,
                            timeout = 1,
                            healthy = {
                                http_statuses = {200},
                                interval = 0.5,
                            },
                            unhealthy = {
                              http_statuses = { 404 },
                            },
                        },
                    },
                },
            })

            ngx.sleep(3)
            ngx.say(etcd.checker.EVENT_SOURCE)
        }
    }
--- request
GET /t
--- timeout: 10
--- no_error_log
[error]
--- response_body
lua-resty-healthcheck [etcd-cluster-health-check]



=== TEST 5: enable health check fail with TLS verify
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
                cluster_healthcheck = {
                    shm_name = 'test_shm',
                    checks = {
                        active = {
                            type = "https",
                            timeout = 1,
                            healthy = {
                                http_statuses = {200},
                                interval = 0.5,
                            },
                            unhealthy = {
                              http_statuses = { 404 },
                            },
                        },
                    },
                },
            })

            ngx.sleep(3)
        }
    }
--- request
GET /t
--- timeout: 10
--- error_log eval
qr /18: self signed certificate/
