use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);

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

    init_by_lua_block {
        function io_opopen(cmd)
            local handle, err = io.popen(cmd)
            if not handle then
                ngx.log(ngx.ERR, "failed to open: ", err)
                return
            end
            local result, err = handle:read("*a")
            handle:close()
            if not result then
                ngx.log(ngx.ERR, "failed to read: ", err)
                return
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

=== TEST 1: check disable etcd cluster health check by default
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
        }
    }
--- request
GET /t
--- no_error_log eval
qr/enable etcd cluster health check/



=== TEST 2: enable etcd cluster health check with minimal configuration
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
                cluster_healthcheck ={
                    shm_name = 'test_shm',
                }
            })
        }
    }
--- request
GET /t
--- grep_error_log eval
qr/success to add new health check target: 127.0.0.1:\d+/
--- grep_error_log_out
success to add new health check target: 127.0.0.1:12379
success to add new health check target: 127.0.0.1:22379
success to add new health check target: 127.0.0.1:32379
--- no_error_log
[error]



=== TEST 3: check unsupported for the etcd version < v3.3.0
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                api_prefix = "/v3alpha",
                http_host = {
                    "http://127.0.0.1:12379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'root',
                password = 'abc123',
                cluster_healthcheck = {
                    shm_name = 'test_shm',
                }
            })
        }
    }
--- request
GET /t
--- error_log eval
qr/unsupported health check for the etcd version < v3.3.0/



=== TEST 4: check user config override default config
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
                cluster_healthcheck = {
                    shm_name = 'test_shm',
                    checks = {
                        active = {
                            http_path = "/wrong_health_check_endpoint",
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
--- ignore_response
--- error_log eval
[qr/unhealthy HTTP increment.*127.0.0.1:12379/,
qr/unhealthy HTTP increment.*127.0.0.1:22379/,
qr/unhealthy HTTP increment.*127.0.0.1:32379/]



=== TEST 5: mock tcp connect timeout and recovery, report the node unhealthy and health
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
                cluster_healthcheck = {
                    shm_name = 'test_shm',
                    checks = {
                        active = {
                            unhealthy = {
                                interval = 0.5,
                            },
                        },
                    },
                },
            })

            local network_isolation_cmd = "export PATH=$PATH:/sbin && iptables -A INPUT -p tcp --dport 12379 -j DROP"
            io_opopen(network_isolation_cmd)

            ngx.sleep(1)

            local res, err = etcd:set("/healthcheck", "yes")

            local network_recovery_cmd = "export PATH=$PATH:/sbin && iptables -D INPUT -p tcp --dport 12379 -j DROP"
            io_opopen(network_recovery_cmd)

            ngx.sleep(2)
        }
    }
--- request
GET /t
--- timeout: 10
--- ignore_response
--- error_log eval
[qr/unhealthy TCP increment.*127.0.0.1:12379/,
qr/healthy SUCCESS increment.*127.0.0.1:12379/]



=== TEST 6: mock etcd node down, report the node unhealthy and choose another health node next time
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
                cluster_healthcheck = {
                    shm_name = 'test_shm',
                }
            })

	        local res, err = etcd:set("/healthcheck", "yes")
            ngx.sleep(0.1)
            res, err = etcd:set("/healthcheck", "yes")
            res, err = etcd:get("/healthcheck")
            ngx.say(res.body.kvs[1].value)
        }
    }
--- request
GET /t
--- timeout: 10
--- response_body eval
qr/yes/
--- grep_error_log eval
qr/unhealthy TCP increment.*/
--- grep_error_log_out eval
qr/unhealthy TCP increment.*127.0.0.1:42379/



=== TEST 7: mock network partition and recovery, report the node unhealthy and health
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
                cluster_healthcheck = {
                    shm_name = 'test_shm',
                    checks = {
                        active = {
                            unhealthy = {
                                interval = 0.5,
                            },
                        },
                    },
                },
            })

            io_opopen("export PATH=$PATH:/sbin && iptables -A INPUT -p tcp --dport 22380 -j DROP")
            io_opopen("export PATH=$PATH:/sbin && iptables -A INPUT -p tcp --dport 32380 -j DROP")

            ngx.sleep(1)

            local res, err = etcd:set("/network/partition", "test")

            io_opopen("export PATH=$PATH:/sbin && iptables -D INPUT -p tcp --dport 22380 -j DROP")
            io_opopen("export PATH=$PATH:/sbin && iptables -D INPUT -p tcp --dport 32380 -j DROP")

            ngx.sleep(2)
        }
    }
--- request
GET /t
--- timeout: 10
--- ignore_response
--- error_log eval
[qr/unhealthy TCP increment.*127.0.0.1:12379/,
qr/healthy SUCCESS increment.*127.0.0.1:12379/]