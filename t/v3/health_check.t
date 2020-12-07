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
            assert(etcd.failure_times == nil)
            assert(etcd.failure_window == nil)
            assert(etcd.disable_duration == nil)
        }
    }
--- request
GET /t
--- no_error_log
[error]



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

            assert(etcd.failure_times == 1)
            assert(etcd.failure_window == 1)
            assert(etcd.disable_duration == 100)
        }
    }
--- request
GET /t
--- no_error_log
[error]



=== TEST 4: verify `failure_window` works
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
                    failure_window = 3,
                    failure_times = 5,
                },
            })

            etcd:set("/test", { a='abc'})
            local counter = ngx.shared["etcd_cluster_health_check"]:get("http://127.0.0.1:42379")
            assert(counter == 1)
            ngx.sleep(1)

            etcd:set("/test", { a='abc'})
            counter = ngx.shared["etcd_cluster_health_check"]:get("http://127.0.0.1:42379")
            assert(counter == 2)
            ngx.sleep(2)

            etcd:set("/test", { a='abc'})
            counter = ngx.shared["etcd_cluster_health_check"]:get("http://127.0.0.1:42379")
            assert(counter == 1)

            ngx.say("all down")
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body
all down



=== TEST 5: verify `failure_times` works
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
                    failure_window = 3,
                    failure_times = 2,
                    disable_duration = 0,
                },
            })

            etcd:set("/test", { a='abc'})
            etcd:set("/test", { a='abc'})
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

            local res, err = etcd:set("/test", { a='abc'})
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
                    disable_duration = 0
                },
            })

            local res, err = etcd:set("/test", { a='abc'})
            ngx.sleep(0.1)
        }
    }
--- request
GET /t
--- error_log eval
qr/restore an endpoint to health: http:\/\/127.0.0.1:42379/



=== TEST 8: one endpoint only trigger mark unhealthy and restore once
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
                    disable_duration = 1
                },
            })

            etcd1:set("/test", { a='abc'})
            etcd1:set("/test", { a='abc'})

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
                    disable_duration = 1
                },
            })

            etcd2:set("/test", { a='abc'})
            etcd2:set("/test", { a='abc'})

            assert(tostring(etcd1) ~= tostring(etcd2))
            local pending_count = ngx.timer.pending_count()
            assert(pending_count == 1)

            ngx.sleep(1.5)
            ngx.say("all down")
        }
    }
--- request
GET /t
--- timeout: 5
--- response_body
all down
