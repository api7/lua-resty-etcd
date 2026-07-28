use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);
plan 'no_plan';

# etcd coalesces watch responses into a single body read whenever they are
# written close enough together (very common once progress_notify is on), and a
# real etcd cannot be driven into that state reliably -- so each test below uses
# a fake endpoint that emits a fixed, hand-crafted coalesced read. The point of
# the fix under test is that the response holding the events is NOT necessarily
# the last one in the read, so we exercise both orderings and an interleaving.

# [event, progress]: event (rev 7) followed by a progress notification (rev 9).
our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    server {
        listen 1985;
        location /v3/watch {
            content_by_lua_block {
                ngx.print('{"result":{"header":{"revision":"7"},"events":' ..
                          '[{"type":"PUT","kv":{"key":"L3Rlc3Q=","value":"ImFiYyI=",' ..
                          '"mod_revision":"7"}}]}}\n' ..
                          '{"result":{"header":{"revision":"9"}}}\n')
            }
        }
    }
_EOC_

# [progress, event]: progress notification (rev 7) followed by an event (rev 9).
our $HttpConfigProgressFirst = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    server {
        listen 1985;
        location /v3/watch {
            content_by_lua_block {
                ngx.print('{"result":{"header":{"revision":"7"}}}\n' ..
                          '{"result":{"header":{"revision":"9"},"events":' ..
                          '[{"type":"PUT","kv":{"key":"L3Rlc3Q=","value":"ImFiYyI=",' ..
                          '"mod_revision":"9"}}]}}\n')
            }
        }
    }
_EOC_

# [event, progress, event]: an event (rev 7), a progress notification (rev 8),
# and a second event (rev 9) all in one read.
our $HttpConfigInterleaved = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    server {
        listen 1985;
        location /v3/watch {
            content_by_lua_block {
                ngx.print('{"result":{"header":{"revision":"7"},"events":' ..
                          '[{"type":"PUT","kv":{"key":"L3Rlc3Q=","value":"ImFiYyI=",' ..
                          '"mod_revision":"7"}}]}}\n' ..
                          '{"result":{"header":{"revision":"8"}}}\n' ..
                          '{"result":{"header":{"revision":"9"},"events":' ..
                          '[{"type":"PUT","kv":{"key":"L3Rlc3Qy","value":"ImJjZCI=",' ..
                          '"mod_revision":"9"}}]}}\n')
            }
        }
    }
_EOC_

run_tests();

__DATA__

=== TEST 1: a coalesced read keeps the events of every response it contains
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = "http://127.0.0.1:1985",
            })
            if not etcd then
                ngx.say("failed to new: ", err)
                return
            end

            local res_func, err = etcd:watchdir("/test", {timeout = 5})
            if not res_func then
                ngx.say("failed to watchdir: ", err)
                return
            end

            local res, err = res_func()
            if not res then
                ngx.say("failed to read watch: ", err)
                return
            end

            -- The read is [event(rev 7), progress(rev 9)]. We report the
            -- progress notification's revision (9, the last response in the
            -- read) while still delivering the rev-7 event: a progress
            -- notification guarantees nothing happened between the event and
            -- it, so the caller can safely advance start_revision past 9.
            ngx.say("revision: ", res.result.header.revision)
            local events = res.result.events
            ngx.say("events: ", events and #events or 0)
            if events and events[1] then
                ngx.say("key: ", events[1].kv.key)
                ngx.say("value: ", events[1].kv.value)
            end
        }
    }
--- request
GET /t
--- response_body
revision: 9
events: 1
key: /test
value: abc
--- no_error_log
[error]



=== TEST 2: a coalesced read keeps the event when it is the last response
--- http_config eval: $::HttpConfigProgressFirst
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = "http://127.0.0.1:1985",
            })
            if not etcd then
                ngx.say("failed to new: ", err)
                return
            end

            local res_func, err = etcd:watchdir("/test", {timeout = 5})
            if not res_func then
                ngx.say("failed to watchdir: ", err)
                return
            end

            local res, err = res_func()
            if not res then
                ngx.say("failed to read watch: ", err)
                return
            end

            -- The read is [progress(rev 7), event(rev 9)]. The event is the
            -- last response, so its revision (9) is reported and its event
            -- delivered.
            ngx.say("revision: ", res.result.header.revision)
            local events = res.result.events
            ngx.say("events: ", events and #events or 0)
            if events and events[1] then
                ngx.say("key: ", events[1].kv.key)
                ngx.say("value: ", events[1].kv.value)
            end
        }
    }
--- request
GET /t
--- response_body
revision: 9
events: 1
key: /test
value: abc
--- no_error_log
[error]



=== TEST 3: a coalesced read keeps events from every response when interleaved
--- http_config eval: $::HttpConfigInterleaved
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({
                protocol = "v3",
                http_host = "http://127.0.0.1:1985",
            })
            if not etcd then
                ngx.say("failed to new: ", err)
                return
            end

            local res_func, err = etcd:watchdir("/test", {timeout = 5})
            if not res_func then
                ngx.say("failed to watchdir: ", err)
                return
            end

            local res, err = res_func()
            if not res then
                ngx.say("failed to read watch: ", err)
                return
            end

            -- The read is [event(rev 7), progress(rev 8), event(rev 9)]. Both
            -- events must survive, in order, under the highest revision (9).
            ngx.say("revision: ", res.result.header.revision)
            local events = res.result.events
            ngx.say("events: ", events and #events or 0)
            if events then
                for i = 1, #events do
                    ngx.say("key", i, ": ", events[i].kv.key,
                            " value", i, ": ", events[i].kv.value)
                end
            end
        }
    }
--- request
GET /t
--- response_body
revision: 9
events: 2
key1: /test value1: abc
key2: /test2 value2: bcd
--- no_error_log
[error]
