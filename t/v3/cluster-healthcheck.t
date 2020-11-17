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

=== TEST 1: enable etcd cluster health check with minimal configuration
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
                timeout = 5,
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



=== TEST 2: mock etcd node down, report unhealthy node
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
                timeout = 5,
                cluster_healthcheck ={
                    shm_name = 'test_shm',
                }
            })

            local res, err = etcd:set("/test", { a='abc'})
            ngx.sleep(0.1)
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body eval
qr/connection refused/
--- grep_error_log eval
qr/unhealthy TCP increment.*/
--- grep_error_log_out eval
qr/unhealthy TCP increment.*127.0.0.1:42379/



=== TEST 3: report unhealthy node, choose a healthy node to complete the read and write
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
                timeout = 5,
                cluster_healthcheck ={
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
--- response_body eval
qr/yes/



=== TEST 4: mock network partitions and report unhealthy nodes
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
                timeout = 1,
                cluster_healthcheck ={
                    shm_name = 'test_shm',
                }
            })

            local network_isolation_cmd = "export PATH=$PATH:/sbin && iptables -A INPUT -p tcp --dport 12379 -j DROP"
            io.popen(network_isolation_cmd)

            local res, err = etcd:set("/test", { a='abc'})

            local network_recovery_cmd = "export PATH=$PATH:/sbin && iptables -D INPUT -p tcp --dport 12379 -j DROP"
            io.popen(network_recovery_cmd)

            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body eval
qr/timeout/
--- grep_error_log eval
qr/unhealthy TCP increment.*/
--- grep_error_log_out eval
qr/unhealthy TCP increment.*127.0.0.1:12379/
