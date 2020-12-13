use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);
workers(2);

my $etcd_version = `etcd --version`;
if ($etcd_version =~ /^etcd Version: 2/ || $etcd_version =~ /^etcd Version: 3.1./ || $etcd_version =~ /^etcd Version: 3.2./) {
    plan(skip_all => "etcd is too old, skip v3 protocol");
} else {
    my $enable_tls = $ENV{ETCD_ENABLE_TLS};
    if ($enable_tls eq "TRUE") {
        plan(skip_all => "skip test cases with auth when TLS is enabled");
    } else {
        plan 'no_plan';
    }
}

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    lua_shared_dict etcd_cluster_health_check 8m;
_EOC_

run_tests();

__DATA__

=== TEST 1: disable health check by default
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

            assert(etcd.shm_name == nil)
            assert(etcd.max_fails == nil)
            assert(etcd.fail_timeout == nil)

            local res, err = etcd:set("/health_check", "disabled")
            res, err = etcd:get("/health_check")
            ngx.say(res.body.kvs[1].value)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
disabled



=== TEST 2: failed enable health check with wrong shm_name
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
                health_check = {
                    shm_name = "wrong_shm_name",
                },
            })

            ngx.say(err)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
failed to get ngx.shared dict: wrong_shm_name



=== TEST 3: valid default config values
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
                health_check = {
                    shm_name = "etcd_cluster_health_check",
                },
            })

            assert(etcd.max_fails == 1)
            assert(etcd.fail_timeout == 10)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 4: verify `fail_timeout` works
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'root',
                password = 'abc123',
                health_check = {
                    shm_name = "etcd_cluster_health_check",
                    fail_timeout = 3,
                    max_fails = 5,
                },
            })

            local key = ngx.worker.id() .. "-" .. "http://127.0.0.1:42379"
            etcd:set("/fail_timeout", "works")
            local counter = ngx.shared["etcd_cluster_health_check"]:get(key)
            assert(counter == 1)
            ngx.sleep(1)

            etcd:set("/fail_timeout", "works")
            counter = ngx.shared["etcd_cluster_health_check"]:get(key)
            assert(counter == 2)
            ngx.sleep(2)

            etcd:set("/fail_timeout", "works")
            counter = ngx.shared["etcd_cluster_health_check"]:get(key)
            assert(counter == 1)

            ngx.say("all down")
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
all down



=== TEST 5: verify `max_fails` works
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'root',
                password = 'abc123',
                health_check = {
                    shm_name = "etcd_cluster_health_check",
                    fail_timeout = 1,
                    max_fails = 2,
                },
            })

            etcd:set("/max_fails", "works")
            etcd:set("/max_fails", "works")
            local pending_count = ngx.timer.pending_count()
            assert(pending_count == 1)
            ngx.say("all down")
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
all down



=== TEST 6: report unhealthy endpoint
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'root',
                password = 'abc123',
                health_check = {
                    shm_name = "etcd_cluster_health_check",
                },
            })

            local res, err = etcd:set("/report", "unhealthy")
        }
    }
--- request
GET /t
--- error_log eval
qr/report an endpoint failure: http:\/\/127.0.0.1:42379/



=== TEST 7: restore endpoint to health
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'root',
                password = 'abc123',
                health_check = {
                    shm_name = "etcd_cluster_health_check",
                    fail_timeout = 1,
                },
            })

            local res, err = etcd:set("/restore", "unhealthy")
            ngx.sleep(1.1)
        }
    }
--- request
GET /t
--- error_log eval
qr/restore an endpoint to health: http:\/\/127.0.0.1:42379/



=== TEST 8: endpoint fails shared by Lua VM, trigger by different etcd client configurations
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd1, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'root',
                password = 'abc123',
                health_check = {
                    shm_name = "etcd_cluster_health_check",
                    max_fails = 3,
                    fail_timeout = 3,
                },
            })
            etcd1:set("/shared_in_worker", "etcd1")
            etcd1:set("/shared_in_worker", "etcd1")
            etcd1:set("/shared_in_worker", "etcd1")

            local etcd2, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'root',
                password = 'abc123',
                health_check = {
                    shm_name = "etcd_cluster_health_check",
                    max_fails = 5,
                    fail_timeout = 3,
                },
            })
            etcd2:set("/shared_in_worker", "etcd2")
            etcd2:set("/shared_in_worker", "etcd2")

            local key = ngx.worker.id() .. "-" .. "http://127.0.0.1:42379"
            local fails, err = ngx.shared["etcd_cluster_health_check"]:get(key)
            assert(fails == 5)

            assert(tostring(etcd1) ~= tostring(etcd2))
            local pending_count = ngx.timer.pending_count()
            assert(pending_count == 2)

            ngx.say("all down")
        }
    }
--- request
GET /t
--- response_body
all down



=== TEST 9: no healthy endpoints when enable health check
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
                health_check = {
                    shm_name = "etcd_cluster_health_check",
                },
            })

            for _, endpoint in ipairs(etcd.endpoints) do
                endpoint.health_status = 0
            end
            local res, err = etcd:set("/no_healthy_endpoint", "yes")
        }
    }
--- request
GET /t
--- error_code: 500
--- error_log eval
qr/has no health etcd endpoint/
