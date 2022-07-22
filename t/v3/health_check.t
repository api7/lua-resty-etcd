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
            local health_check, err = require "resty.etcd.health_check" .init({
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
            local health_check, err = require "resty.etcd.health_check" .init({
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
                user = 'root',
                password = 'abc123',
            })

            local res, err = etcd:set("/trigger_unhealthy", { a='abc'})
            ngx.say(err)
        }
    }
--- request
GET /t
--- error_log eval
qr/update endpoint: http:\/\/127.0.0.1:42379 to unhealthy/
--- response_body
http://127.0.0.1:42379: connection refused



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
            })

            local body_chunk_fun, err = etcd:watch("/trigger_unhealthy")
            if not body_chunk_fun then
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- error_log eval
qr/update endpoint: http:\/\/127.0.0.1:42379 to unhealthy/
--- response_body
http://127.0.0.1:42379: connection refused



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
                user = 'root',
                password = 'abc123',
            })

            -- make sure to select http://127.0.0.1:42379 twice
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
--- request
GET /t
--- response_body
2
--- no_error_log
[error]



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
                user = 'root',
                password = 'abc123',
            })

            etcd:set("/get_target_status", { a='abc'})

            local healthy = health_check.get_target_status("http://127.0.0.1:42379")
            ngx.say(healthy)
        }
    }
--- request
GET /t
--- response_body
false
--- no_error_log
[error]



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
                user = 'root',
                password = 'abc123',
            })

            local res, err

            -- make sure to select http://127.0.0.1:42379 once and trigger it to unhealthy
            for i = 1, 3 do
                 res, err = etcd:set("/fail_timeout", "value")
            end

            -- ensure that unhealthy http://127.0.0.1:42379 are no longer selected
            for i = 1, 3 do
                 res, err = etcd:get("/fail_timeout")
                 assert(res.body.kvs[1].value == "value")
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- timeout: 5
--- response_body
done
--- error_log
update endpoint: http://127.0.0.1:42379 to unhealthy
--- no_error_log
[error]



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

            health_check.report_failure("http://127.0.0.1:12379")
            health_check.report_failure("http://127.0.0.1:22379")
            health_check.report_failure("http://127.0.0.1:32379")

            local res, err = etcd:set("/no_healthy_endpoint", "hello")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
has no healthy etcd endpoint available
--- no_error_log
[error]



=== TEST 10: `health_check` shared by different etcd clients
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 3,
                max_fails = 2,
            })

            local etcd1, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'root',
                password = 'abc123',
            })

            local etcd2, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
                user = 'root',
                password = 'abc123',
            })

            assert(tostring(etcd1) ~= tostring(etcd2))
            etcd1:set("/etcd1", "hello")
            etcd2:set("/etcd2", "hello")

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log eval
qr/update endpoint: http:\/\/127.0.0.1:42379 to unhealthy/



=== TEST 11: mock etcd error and report fault
--- http_config eval: $::HttpConfig
--- config
    location /v3/auth/authenticate {
        content_by_lua_block { -- mock normal authenticate response
            ngx.print([[{
              body = '{"header":{"cluster_id":"17237436991929493444","member_id":"9372538179322589801","revision":"40","raft_term":"633"},"token":"KicnFPYazDaiMHBG.74"}',
              reason = "OK",
              status = 200
            }]])
        }
    }

    location /v3/kv/put {
        content_by_lua_block { -- mock abnormal put key response
            ngx.print([[{
              body = '{"error":"etcdserver: request timed out","message":"etcdserver: request timed out","code":14}',
              reason = "Service Unavailable",
              status = 503,
            }]])
        }
    }

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
                    "http://127.0.0.1:12379",
                },
                user = 'root',
                password = 'abc123',
            })

            etcd.endpoints[1].full_prefix="http://localhost:1984/v3" -- replace the endpoint with mock
            etcd.endpoints[1].http_host="http://localhost:1984"
            local res, err = etcd:set("/etcd_error", "hello")
            local fails, err = ngx.shared["etcd_cluster_health_check"]:get("http://localhost:1984")
            ngx.say(fails)
        }
    }
--- request
GET /t
--- response_body
1
--- error_log eval
qr/update endpoint: http:\/\/localhost:1984 to unhealthy/



=== TEST 12: test if retry works for request_uri
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 10,
                max_fails = 3,
                retry = true,
            })

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

            local res, err
            for i = 1, 3 do
                res, err = etcd:set("/trigger_unhealthy", "abc")
            end
            check_res(res, err)
            local res, err = etcd:get("/trigger_unhealthy")
            check_res(res, err, "abc")

            -- There are 5 times read and write operations to etcd have occurred here
            -- 3 set, 1 get, 1 auth
            -- actual 8 times choose endpoint, retry every time 42379 is selected
            -- 42379 marked as unhealthy after 3 seleced
        }
    }
--- request
GET /t
--- error_log eval
qr/update endpoint: http:\/\/127.0.0.1:42379 to unhealthy/
--- response_body
checked val as expect: abc



=== TEST 13: test if retry works for request_chunk
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 10,
                max_fails = 3,
                retry = true,
            })

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

            local body_chunk_fun, err = etcd:watch("/trigger_unhealthy", {timeout = 0.5})
            check_res(body_chunk_fun, err)

            ngx.timer.at(0.1, function ()
                for i = 1, 3 do
                    etcd:set("/trigger_unhealthy", "abc")
                end
            end)

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
--- error_log eval
qr/update endpoint: http:\/\/127.0.0.1:42379 to unhealthy/
--- response_body_like eval
qr/1:.*"created":true.*
2:.*"value":"abc".*
3:.*"value":"abc".*
4:.*"value":"abc".*
timeout/
--- timeout: 5



=== TEST 14: test retry failure could return correctly
--- http_config eval: $::HttpConfig
--- config
    location /v3/auth/authenticate {
        content_by_lua_block { -- mock normal authenticate response
            ngx.print([[{
              body = '{"header":{"cluster_id":"17237436991929493444","member_id":"9372538179322589801","revision":"40","raft_term":"633"},"token":"KicnFPYazDaiMHBG.74"}',
              reason = "OK",
              status = 200
            }]])
        }
    }

    location /v3/kv/put {
        content_by_lua_block { -- mock abnormal put key response
            ngx.status = 500
            ngx.print([[{
              body = '{"error":"etcdserver: request timed out","message":"etcdserver: request timed out","code":14}',
              reason = "Service Unavailable",
              status = 503,
            }]])
            ngx.say("this is my own error page content")
            ngx.exit(500)
        }
    }

    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                shm_name = "etcd_cluster_health_check",
                fail_timeout = 10,
                max_fails = 3,
                retry = true,
            })

            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:12379",
                },
            })
            etcd.endpoints[1].full_prefix="http://127.0.0.1:1984/v3" -- replace the endpoint with mock
            etcd.endpoints[1].http_host="http://127.0.0.1:1984"

            local res, err = etcd:set("/etcd_error", "hello")
            local fails = ngx.shared["etcd_cluster_health_check"]:get("http://127.0.0.1:1984")
            ngx.say(fails)
            if err ~= "has no healthy etcd endpoint available" then
                ngx.say(err)
                ngx.exit(200)
            end
        }
    }
--- request
GET /t
--- error_log eval
qr/update endpoint: http:\/\/127.0.0.1:1984 to unhealthy/
--- response_body
3



=== TEST 15: (round robin) has no healthy etcd endpoint, directly return an error message
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                retry = true,
            })

            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:12379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
            })

            health_check.report_failure("http://127.0.0.1:12379")
            health_check.report_failure("http://127.0.0.1:22379")
            health_check.report_failure("http://127.0.0.1:32379")

            local res, err = etcd:set("/test/etcd/healthy", "hello")
            ngx.say(err)
        }
    }
--- request
GET /t
--- response_body
has no healthy etcd endpoint available
--- no_error_log
[error]



=== TEST 16: (round robin) passive stop one endpoint and successfully insert data
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                retry = true,
            })

            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
            })

            local res, err = etcd:set("/test/etcd/healthy", "hello")
            if err then
                ngx.say(err)
            else
                ngx.say("SET OK")
            end
        }
    }
--- request
GET /t
--- response_body
SET OK
--- error_log eval
qr/update endpoint: http:\/\/127.0.0.1:42379 to unhealthy/



=== TEST 17: (round robin) actively stop one endpoint and successfully insert data
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check, err = require "resty.etcd.health_check" .init({
                retry = true,
            })

            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:12379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
            })

            health_check.report_failure("http://127.0.0.1:12379")

            local res, err = etcd:set("/test/etcd/healthy", "hello")
            if err then
                ngx.say(err)
            else
                ngx.say("SET OK")
            end
        }
    }
--- request
GET /t
--- response_body
SET OK
--- error_log eval
qr/update endpoint: http:\/\/127.0.0.1:12379 to unhealthy/



=== TEST 18: (round robin) default round robin health check insert data
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
            })

            local res
            res, err = etcd:set("/test/etcd/unhealthy", "hello")
            ngx.say(err)
            res, err = etcd:set("/test/etcd/healthy", "hello")
            if err == nil then
                ngx.say("http://127.0.0.1:22379: OK")
            end
        }
    }
--- request
GET /t
--- response_body
http://127.0.0.1:42379: connection refused
http://127.0.0.1:22379: OK
--- error_log eval
qr/update endpoint: http:\/\/127.0.0.1:42379 to unhealthy/



=== TEST 19: test health check running mode
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
            })

            local health_check = require("resty.etcd.health_check")
            local mode = health_check.get_check_mode()
            if mode == health_check.ROUND_ROBIN_MODE then
                ngx.say("passed")
            end

            health_check.init({
                shm_name = "etcd_cluster_health_check",
            })

            mode = health_check.get_check_mode()
            if mode == health_check.SHARED_DICT_MODE then
                ngx.say("passed")
            end
        }
    }
--- request
GET /t
--- response_body
passed
passed
--- grep_error_log eval
qr/healthy check use \S+ \w+/
--- grep_error_log_out
healthy check use round robin
healthy check use ngx.shared dict



=== TEST 20: disable health check
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local health_check = require("resty.etcd.health_check")
            health_check.disable()
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = {
                    "http://127.0.0.1:42379",
                    "http://127.0.0.1:22379",
                    "http://127.0.0.1:32379",
                },
            })

            local res
            res, err = etcd:set("/test/etcd/unhealthy", "hello")
            ngx.say(err)
            res, err = etcd:set("/test/etcd/healthy", "hello")
            if err == nil then
                ngx.say("http://127.0.0.1:22379: OK")
            else
                ngx.say(err)
            end
        }
    }
--- request
GET /t
--- response_body
http://127.0.0.1:42379: connection refused
http://127.0.0.1:22379: OK
--- no_error_log eval
qr/update endpoint: http:\/\/127.0.0.1:42379 to unhealthy/



=== TEST 21: health check disabled mode
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
            })

            local health_check = require("resty.etcd.health_check")
            local mode = health_check.get_check_mode()

            health_check.init({
                shm_name = "etcd_cluster_health_check",
            })

            mode = health_check.get_check_mode()
            if mode == health_check.SHARED_DICT_MODE then
                ngx.say("passed")
            end

            health_check.disable()

            mode = health_check.get_check_mode()
            if mode == health_check.DISABLED_MODE then
                ngx.say("passed")
            end
        }
    }
--- request
GET /t
--- response_body
passed
passed



=== TEST 22: ring balancer
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
            })

            local res
            for i = 1, 3 do
                res, err = etcd:set("/ring_balancer", "abc")
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done
--- error_log
choose_endpoint(): choose endpoint: http://127.0.0.1:12379
choose_endpoint(): choose endpoint: http://127.0.0.1:22379
choose_endpoint(): choose endpoint: http://127.0.0.1:32379
