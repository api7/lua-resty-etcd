use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);
plan 'no_plan';

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';

    # A fake etcd watch endpoint replying with two watch responses in a single
    # body chunk: one carrying an event, followed by a progress notification.
    # etcd coalesces responses like this whenever they are written close enough
    # together, and a real etcd cannot be driven into that state reliably.
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

            -- the last response of the read is the progress notification
            ngx.say("revision: ", res.result.header.revision)
            local events = res.result.events
            ngx.say("events: ", events and #events or 0)
            if events and events[1] then
                ngx.say("key: ", events[1].kv.key)
                ngx.say("value: ", events[1].kv.value)
            end
        }
    }
--- response_body
revision: 9
events: 1
key: /test
value: abc
--- no_error_log
[error]
