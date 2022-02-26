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
    init_by_lua_block {
        local cjson = require("cjson.safe")

        function check_res(data, err, val, status)
            if err then
                ngx.say("err: ", err)
                ngx.exit(200)
            end

            if val then
                if data and data.body.kvs==nil then
                    ngx.exit(404)
                end
                if data and data.body.kvs and val ~= data.body.kvs[1].value then
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

=== TEST 1: set(key, val) and get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc", {prev_kv = true})
            check_res(res, err)

            local data, err = etcd:get("/test")
            check_res(data, err, "abc")

            local data, err = etcd:get("")
            check_res(data, nil, err)

            local data, err = etcd:set("")
            check_res(data, nil, err)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked val as expect: abc
checked val as expect: key should not be empty
checked val as expect: key should not be empty



=== TEST 2: readdir(key)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local tab_nkeys     = require "table.nkeys"
            local etcd, err = require "resty.etcd" .new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:set("/dir", "abc")
            check_res(res, err)

            local res, err = etcd:set("/dir/a", "abca")
            check_res(res, err)

            local data, err = etcd:readdir("/dir")
            if tab_nkeys(data.body.kvs) == 2 then
                ngx.say("ok")
                ngx.exit(200)
            else
                ngx.say("failed")
            end

        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
ok



=== TEST 3: watch(key)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            ngx.timer.at(0.1, function ()
                etcd:set("/test", "bcd3")
            end)

            local cur_time = ngx.now()
            local body_chunk_fun, err = etcd:watch("/test", {timeout = 0.5})
            if not body_chunk_fun then
                ngx.say("failed to watch: ", err)
            end

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
--- no_error_log
[error]
--- response_body_like eval
qr/1:.*"created":true.*
2:.*"value":"bcd3".*
timeout/
--- timeout: 5



=== TEST 4: watch and watchcancel(key)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
            check_res(res, err)

            ngx.timer.at(0.1, function ()
                etcd:set("/test", "bcd3")
            end)

            ngx.timer.at(0.2, function ()
                etcd:set("/test", "bcd4")
            end)

            local cur_time = ngx.now()
            local body_chunk_fun, err, http_cli = etcd:watch("/test", {timeout = 0.5, need_cancel = true})

            if type(http_cli) ~= "table" then
                ngx.say("need_cancel failed")
            end

            if not body_chunk_fun then
                ngx.say("failed to watch: ", err)
            end

            local chunk, err = body_chunk_fun()
            ngx.say("created: ", chunk.result.created)
            local chunk, err = body_chunk_fun()
            ngx.say("value: ", chunk.result.events[1].kv.value)

            local res, err = etcd:watchcancel(http_cli)
            if not res then
                ngx.say("failed to cancel: ", err)
            end

            local chunk, err = body_chunk_fun()
            ngx.say(err)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
created: true
value: bcd3
closed
ok
--- timeout: 5



=== TEST 5: watchdir(key)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:set("/wdir", "abc")
            check_res(res, err)

            ngx.timer.at(0.05, function ()
                etcd:set("/wdir-", "bcd3")
            end)

            ngx.timer.at(0.1, function ()
                etcd:set("/wdir/", "bcd4")
            end)

            ngx.timer.at(0.2, function ()
                etcd:set("/wdir/a", "bcd4a")
            end)

            ngx.timer.at(0.3, function ()
                etcd:delete("/wdir/a")
            end)

            local cur_time = ngx.now()
            local body_chunk_fun, err = etcd:watchdir("/wdir/", {timeout = 1.5})
            if not body_chunk_fun then
                ngx.say("failed to watch: ", err)
            end

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
--- no_error_log
[error]
--- response_body_like eval
qr/1:.*"created":true.*
2:.*"value":"bcd4".*
3:.*"value":"bcd4a".*
4:.*"type":"DELETE".*
timeout/
--- timeout: 5


=== TEST 6: watchdir(key=="")
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:set("/wdir", "abc")
            check_res(res, err)

            ngx.timer.at(0.05, function ()
                etcd:set("/wdir-", "bcd3")
            end)

            ngx.timer.at(0.1, function ()
                etcd:set("/wdir/", "bcd4")
            end)

            ngx.timer.at(0.2, function ()
                etcd:set("/wdir/a", "bcd4a")
            end)

            ngx.timer.at(0.3, function ()
                etcd:delete("/wdir/a")
            end)

            local cur_time = ngx.now()
            local body_chunk_fun, err = etcd:watchdir("", {timeout = 1.5})
            if not body_chunk_fun then
                ngx.say("failed to watch: ", err)
            end

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
--- no_error_log
[error]
--- response_body_like eval
qr/1:.*"created":true.*
2:.*"value":"bcd3".*
3:.*"value":"bcd4".*
4:.*"value":"bcd4a".*
5:.*"type":"DELETE".*
timeout/
--- timeout: 5



=== TEST 7: setx(key, val) failed
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:setx("/setxf", "abc")
            check_res(res, err, nil, 200)

            local data, err = etcd:get("/setxf")
            check_res(data, err, "abc", 200)
        }
    }
--- request
GET /t
--- error_code: 404



=== TEST 8: setx(key, val) success
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:set("/setxs", "abc")
            check_res(res, err, nil, 200)

            local res, err = etcd:setx("/setxs", "abd")
            check_res(res, err, nil, 200)

            local data, err = etcd:get("/setxs")
            check_res(data, err, "abd", 200)
        }
    }
--- request
GET /t
--- no_error_log
--- response_body
checked val as expect: abd



=== TEST 9: setnx(key, val)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:delete("/setnx")
            check_res(res, err, nil, 200)

            local res, err = etcd:setnx("/setnx", "aaa")
            check_res(res, err, nil, 200)

            local res, err = etcd:setnx("/setnx", "bbb")
            check_res(res, err, nil, 200)

            local data, err = etcd:get("/setnx")
            check_res(data, err, "aaa", 200)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked val as expect: aaa



=== TEST 10: set extra_headers for request_uri
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                extra_headers = {
                    foo = "bar",
                }
            })
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc", {prev_kv = true})
            check_res(res, err)

            local data, err = etcd:get("/test")
            check_res(data, err, "abc")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked val as expect: abc
--- error_log
request uri headers: {"foo":"bar"}



=== TEST 11: Authorization header will not be overridden
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                extra_headers = {
                    Authorization = "bar",
                }
            })
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc", {prev_kv = true})
            check_res(res, err)

            local data, err = etcd:get("/test")
            check_res(data, err, "abc")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
checked val as expect: abc
--- error_log
request uri headers: {}



=== TEST 12: set extra_headers for request_chunk
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                extra_headers = {
                    foo = "bar",
                }
            })
            local res, err = etcd:set("/test", "abc")
            local body_chunk_fun, _ = etcd:watch("/test", {timeout = 0.5})
            ngx.say("passed")
        }
    }
--- request
GET /t
--- response_body
passed
--- error_log
request chunk headers: {"foo":"bar"}
--- no_error_log
[error]



=== TEST 13: watch response which http chunk contains partial etcd event response
--- http_config eval: $::HttpConfig
--- config
    location /version {
        content_by_lua_block {
            ngx.say('{"etcdserver":"3.4.0","etcdcluster":"3.4.0"}')
        }
    }

    location /v3/watch {
        content_by_lua_block {
            -- payload get from tcpdump while running TEST 3 and split the event response into two chunks

            ngx.say('{"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437","revision":"271","raft_term":"7"},"created":true}}')
            ngx.flush()
            ngx.sleep(0.1)

            -- partial event without trailing new line
            ngx.print('{"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437",')
            ngx.flush()
            ngx.print('"revision":"272","raft_term":"7"},"events"')
            ngx.flush()

            -- key = /test, value = bcd3
            ngx.say(':[{"kv":{"key":"L3Rlc3Q=","create_revision":"156","mod_revision":"272","version":"44","value":"ImJjZDMi"}}]}}')
            ngx.flush()

            -- ensure client timeout
            ngx.sleep(1)
        }
    }

    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new({
              protocol = "v3",
              http_host = {
                "http://127.0.0.1:" .. ngx.var.server_port,
              },
            })
            check_res(etcd, err)

            local cur_time = ngx.now()
            local body_chunk_fun, err = etcd:watch("/test", {timeout = 0.5})
            if not body_chunk_fun then
                ngx.say("failed to watch: ", err)
            end

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
--- no_error_log
[error]
--- response_body_like eval
qr/1:.*"created":true.*
2:.*"value":"bcd3".*
timeout/
--- timeout: 5



=== TEST 14: watch response which one http chunk contains multiple events chunk
--- http_config eval: $::HttpConfig
--- config
    location /version {
        content_by_lua_block {
            ngx.say('{"etcdserver":"3.4.0","etcdcluster":"3.4.0"}')
        }
    }

    location /v3/watch {
        content_by_lua_block {
            -- payload get from tcpdump while running TEST 5 and merge two event response into one http chunk

            ngx.say('{"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437","revision":"290","raft_term":"8"},"created":true}}')
            ngx.flush()
            ngx.sleep(0.1)

            -- one http chunk contains multiple event response, note the new line at the end of first event response
            -- key1 = /wdir/, value1 = bcd4
            -- key2 = /wdir/a, value2 = bcd4a
            ngx.say('{"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437","revision":"292","raft_term":"8"},"events":[{"kv":{"key":"L3dkaXIv","create_revision":"31","mod_revision":"292","version":"22","value":"ImJjZDQi"}}]}}\n{"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437","revision":"293","raft_term":"8"},"events":[{"kv":{"key":"L3dkaXIvYQ==","create_revision":"293","mod_revision":"293","version":"1","value":"ImJjZDRhIg=="}}]}}')
            ngx.flush()

            -- ensure client timeout
            ngx.sleep(1)
        }
    }

    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new({
              protocol = "v3",
              http_host = {
                "http://127.0.0.1:" .. ngx.var.server_port,
              },
            })
            check_res(etcd, err)

            local cur_time = ngx.now()
            local body_chunk_fun, err = etcd:watch("/", {timeout = 0.5})
            if not body_chunk_fun then
                ngx.say("failed to watch: ", err)
            end

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
--- no_error_log
[error]
--- response_body_like eval
qr/1:.*"created":true.*
2:.*"value":"bcd4".*"value":"bcd4a".*
timeout/
--- timeout: 5
