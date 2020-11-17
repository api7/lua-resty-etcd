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

=== TEST 1: mock etcd network partitions and network, report the node unhealthy and health
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
            local handle, err = io_opopen(network_isolation_cmd)

            ngx.sleep(1)

            local res, err = etcd:set("/healthcheck", "yes")

            local network_recovery_cmd = "export PATH=$PATH:/sbin && iptables -D INPUT -p tcp --dport 12379 -j DROP"
            handle, err = io_opopen(network_recovery_cmd)

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
