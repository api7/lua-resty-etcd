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

=== TEST 1: set(key, val) and get
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:set("/test", "abc")
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



=== TEST 4: watchdir(key)
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:set("/wdir", "abc")
            check_res(res, err)

            ngx.timer.at(0.1, function ()
                etcd:set("/wdir", "bcd4")
            end)

            ngx.timer.at(0.2, function ()
                etcd:set("/wdir/a", "bcd4a")
            end)

            ngx.timer.at(0.3, function ()
                etcd:delete("/wdir/a")
            end)

            local cur_time = ngx.now()
            local body_chunk_fun, err = etcd:watchdir("/wdir", {timeout = 1.5})
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



=== TEST 5: setx(key, val) failed
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



=== TEST 6: setx(key, val) success
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



=== TEST 7: setnx(key, val)
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
