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
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;/usr/local/lua-resty-etcd/deps/share/lua/5.1/?.lua;/usr/local/lua-resty-etcd/deps/share/lua/5.1/?/?.lua;;';
    lua_shared_dict etcd_cluster_health_check 8m;
_EOC_

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .new({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 10,
                max_fails = 1,
            })

           ngx.log(ngx.WARN, "health_check: ", require("resty.inspect")(health_check))
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

            ngx.say("all down")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
all down
