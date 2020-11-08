use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);

my $etcd_version = `etcd --version`;
if ($etcd_version =~ /^etcd Version: 2/ || $etcd_version =~ /^etcd Version: 3.1./) {
    plan(skip_all => "etcd is too old, skip v3 protocol");
} else {
    plan 'no_plan';
}

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
_EOC_

run_tests();

__DATA__

=== TEST 1: opt http_host
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local hosts = {
                "http://127.0.0.1:2379",
                "http://etcd",
                "http://apisix-etcd",
                "http://apisix-etcd-headless",
                "http://apisix-etcd-headless.apisix.svc.cluster.local",
            }
            for _, host in ipairs(hosts) do
                local etcd, err = require "resty.etcd" .new({protocol = "v3", http_host = host})

                if etcd then
                    ngx.say(
                        etcd.endpoints[1].scheme, " ",
                        etcd.endpoints[1].host, " ",
                        etcd.endpoints[1].port
                    )
                else
                    ngx.say(err)
                end

            end
            ngx.say('ok')
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
http 127.0.0.1 2379
no resolver defined to resolve "etcd"
no resolver defined to resolve "apisix-etcd"
no resolver defined to resolve "apisix-etcd-headless"
no resolver defined to resolve "apisix-etcd-headless.apisix.svc.cluster.local"
ok
