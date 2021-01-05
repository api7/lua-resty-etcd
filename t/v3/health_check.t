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
                fail_timeout = 5,
                max_fails = 3,
            })
            assert( err == nil)
            assert( health_check.conf ~= nil)

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
            check_res(etcd, err)

            ngx.say("done")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
done



=== TEST 2: default configuration
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .new({
                shm_name = "etcd_cluster_health_check",
            })
            ngx.say(health_check.conf.max_fails)
            ngx.say(health_check.conf.fail_timeout)
        }
    }
--- request
GET /t
--- response_body
1
10
--- no_error_log
[error]



=== TEST 3: bad shm_name
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .new({
                shm_name = "error_shm_name",
            })
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
failed to get ngx.shared dict: error_shm_name
--- no_error_log
[error]



=== TEST 4: trigger unhealthy
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .new({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 10,
                max_fails = 1,
            })
            assert( err == nil)
            assert( health_check.conf ~= nil)

            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'root',
                password = 'abc123',
            })

            local res, err = etcd:set("/trigger_unhealthy", { a='abc'})
            ngx.say("done")
        }
    }
--- request
GET /t
--- error_log eval
qr/update endpoint: http:\/\/127.0.0.1:42379 to unhealthy/
--- response_body
done
