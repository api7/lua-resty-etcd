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
    if (defined($enable_tls) && $enable_tls eq "TRUE") {
        plan(skip_all => "skip test cases with auth when TLS is enabled");
    } else {
        plan 'no_plan';
    }
}

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->main_config) {
        $block->set_value("main_config", "thread_pool grpc-client-nginx-module threads=1;");
    }

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if ((!defined $block->error_log) && (!defined $block->no_error_log)) {
        $block->set_value("no_error_log", "[error]");
    }

});

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
            local health_check, err = require "resty.etcd.health_check" .init({
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
                use_grpc = true,
                user = 'root',
                password = 'abc123',
            })
            check_res(etcd, err)

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: default configuration
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "etcd_cluster_health_check",
            })
            ngx.say(health_check.conf.max_fails)
            ngx.say(health_check.conf.fail_timeout)
        }
    }
--- response_body
1
10



=== TEST 3: bad shm_name
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "error_shm_name",
            })
            ngx.say(err)
        }
    }
--- response_body
failed to get ngx.shared dict: error_shm_name



=== TEST 4: trigger unhealthy with set
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 10,
                max_fails = 1,
            })

            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                use_grpc = true,
                user = 'root',
                password = 'abc123',
                init_count = -1,
            })

            local res, err = etcd:set("/trigger_unhealthy", { a='abc'})
            ngx.say(err)
        }
    }
--- error_log eval
qr/update endpoint: http:\/\/127.0.0.1:42379 to unhealthy/
--- response_body_like eval
qr/.* dial tcp 127.0.0.1:42379: connect: connection refused/



=== TEST 5: trigger unhealthy with watch
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 10,
                max_fails = 1,
            })

            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                use_grpc = true,
                init_count = -1,
            })

            local body_chunk_fun, err = etcd:create_grpc_watch_stream("/trigger_unhealthy", {})
            if not body_chunk_fun then
                ngx.say(err)
            end
        }
    }
--- error_log eval
qr/update endpoint: http:\/\/127.0.0.1:42379 to unhealthy/
--- response_body_like eval
qr/.* dial tcp 127.0.0.1:42379: connect: connection refused/



=== TEST 6: fault count
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 5,
                max_fails = 3,
            })

            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                use_grpc = true,
                user = 'root',
                password = 'abc123',
                init_count = -1,
            })

            -- http://127.0.0.1:42379 will be selected only once
            for i = 1, 4 do
                etcd:set("/fault_count", { a='abc'})
            end

            -- here have actually been 5 reads and writes to etcd, including one to /auth/authenticate

            local fails, err = ngx.shared["etcd_cluster_health_check"]:get("http://127.0.0.1:42379")
            if err then
                ngx.say(err)
            end
            ngx.say(fails)
        }
    }
--- response_body
1



=== TEST 7: check endpoint is healthy
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 3,
                max_fails = 1,
            })

            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                use_grpc = true,
                user = 'root',
                password = 'abc123',
                init_count = -1,
            })

            etcd:set("/get_target_status", { a='abc'})

            local healthy = health_check.get_target_status("http://127.0.0.1:42379")
            ngx.say(healthy)
        }
    }
--- response_body
false



=== TEST 8: make sure `fail_timeout` works
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 2,
                max_fails = 1,
            })

            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                use_grpc = true,
                user = 'root',
                password = 'abc123',
                init_count = -1,
            })

            local res, err

            -- make sure to select http://127.0.0.1:42379 once and trigger it to unhealthy
            for i = 1, 3 do
                 res, err = etcd:set("/fail_timeout", "value")
            end

            -- ensure that unhealthy http://127.0.0.1:42379 are no longer selected
            for i = 1, 3 do
                 res, err = etcd:get("/fail_timeout")
                 assert(res, err)
                 assert(res.body.kvs[1].value == "value")
            end

            ngx.say("done")
        }
    }
--- timeout: 5
--- response_body
done
--- error_log
update endpoint: http://127.0.0.1:42379 to unhealthy



=== TEST 9: has no healthy etcd endpoint, directly return an error message
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 3,
                max_fails = 1,
            })

            health_check.report_failure("http://127.0.0.1:12379")
            health_check.report_failure("http://127.0.0.1:22379")
            health_check.report_failure("http://127.0.0.1:32379")

            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:12379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                use_grpc = true,
                user = 'root',
                password = 'abc123',
            })
            ngx.say(err)
        }
    }
--- response_body
has no healthy etcd endpoint available



=== TEST 10: test if retry works
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 10,
                max_fails = 1,
                retry = true,
            })

            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:52379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                use_grpc = true,
                user = 'root',
                password = 'abc123',
                init_count = -1,
            })

            local res, err
            for i = 1, 4 do
                res, err = etcd:set("/trigger_unhealthy", "abc")
            end
            check_res(res, err)
            local res, err = etcd:get("/trigger_unhealthy")
            check_res(res, err, "abc")
            -- unlike the retry in http version, we will use the same connection if the previous
            -- call is successful
        }
    }
--- grep_error_log eval
qr/update endpoint: http:\/\/127.0.0.1:\d+ to unhealthy/
--- grep_error_log_out
update endpoint: http://127.0.0.1:42379 to unhealthy
update endpoint: http://127.0.0.1:52379 to unhealthy
--- response_body
checked val as expect: abc



=== TEST 11: ring balancer with specific init_count
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check = require("resty.etcd.health_check")
            health_check.disable()
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:12379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                use_grpc = true,
                init_count = 101,
            })

            local res
            for i = 1, 3 do
                res, err = etcd:set("/ring_balancer", "abc")
            end

            ngx.say(etcd.init_count)
        }
    }
--- response_body
105
--- error_log
choose endpoint: http://127.0.0.1:12379
choose endpoint: http://127.0.0.1:22379
