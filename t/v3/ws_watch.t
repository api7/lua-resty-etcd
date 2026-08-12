use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);

my $etcd_version = `etcd --version`;
if ($etcd_version =~ /^etcd Version: 2/ || $etcd_version =~ /^etcd Version: 3.1./
    || $etcd_version =~ /^etcd Version: 3.2./ || $etcd_version =~ /^etcd Version: 3.3./) {
    plan(skip_all => "etcd is too old, progress requests need etcd >= 3.4");
} else {
    plan 'no_plan';
}

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    init_by_lua_block {
        function new_cli()
            local etcd, err = require("resty.etcd").new({
                protocol = "v3",
                http_host = "http://127.0.0.1:2379",
                timeout = 5,
            })
            if not etcd then
                ngx.say("failed to new etcd: ", err)
                ngx.exit(200)
            end
            return etcd
        end

        function current_rev(etcd, key)
            local res, err = etcd:get(key)
            if not res then
                ngx.say("failed to get: ", err)
                ngx.exit(200)
            end
            return tonumber(res.body.header.revision)
        end
    }
_EOC_

# a plain HTTP endpoint that accepts the websocket upgrade request but never
# actually upgrades: the handshake reply is a normal 200 response
our $HttpConfigNoUpgrade = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    server {
        listen 1985;
        location /v3/watch {
            content_by_lua_block {
                ngx.print("not a websocket endpoint")
            }
        }
    }
_EOC_

run_tests();

__DATA__

=== TEST 1: created ack, then a live event while the request side stays open
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd = new_cli()
            assert(etcd:set("/ws_watch/seed", "seed"))
            local rev = current_rev(etcd, "/ws_watch/seed")

            local sess, err = etcd:create_ws_watch_session("/ws_watch",
                                                           {start_revision = rev + 1})
            if not sess then
                ngx.say("failed to create session: ", err)
                return
            end

            local res, err = sess:recv(2)
            if not res then
                ngx.say("failed to recv created ack: ", err)
                return
            end
            ngx.say("created: ", res.result.created == true)

            assert(etcd:set("/ws_watch/live", "abc"))
            res, err = sess:recv(2)
            if not res then
                ngx.say("failed to recv event: ", err)
                return
            end
            local event = res.result.events[1]
            ngx.say("event: ", event.type or "PUT", " ", event.kv.key, "=", event.kv.value)
            sess:close()
        }
    }
--- request
GET /t
--- response_body
created: true
event: PUT /ws_watch/live=abc
--- no_error_log
[error]



=== TEST 2: a progress request on an idle prefix reports the global revision
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd = new_cli()
            assert(etcd:set("/ws_watch/seed", "seed"))
            local rev = current_rev(etcd, "/ws_watch/seed")

            local sess = assert(etcd:create_ws_watch_session("/ws_watch",
                                                             {start_revision = rev + 1}))
            assert(sess:recv(2))   -- created ack

            -- etcd only answers once the watcher is synced; a request landing
            -- in the pre-sync window (<= 100ms) is dropped, so retry once
            ngx.sleep(0.3)
            assert(sess:request_progress())
            local res, err = sess:recv(2)
            if not res then
                assert(sess:request_progress())
                res, err = sess:recv(2)
            end
            if not res then
                ngx.say("failed to recv progress: ", err)
                return
            end
            -- >= rev rather than == rev: anything else sharing the etcd may
            -- have bumped the global revision since current_rev() sampled it
            ngx.say("idle progress at current revision: ",
                    res.result.events == nil
                    and tonumber(res.result.header.revision) >= rev)

            -- writes OUTSIDE the watched prefix produce no events, yet the
            -- barrier must follow the global revision
            for i = 1, 3 do
                assert(etcd:set("/ws_elsewhere/k", "v" .. i))
            end
            assert(sess:request_progress())
            res, err = sess:recv(2)
            if not res then
                ngx.say("failed to recv progress: ", err)
                return
            end
            ngx.say("barrier followed foreign writes: ",
                    res.result.events == nil
                    and tonumber(res.result.header.revision) >= rev + 3)
            sess:close()
        }
    }
--- request
GET /t
--- response_body
idle progress at current revision: true
barrier followed foreign writes: true
--- no_error_log
[error]



=== TEST 3: a stream resumed from the barrier revision survives compaction
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local cjson = require("cjson.safe")
            local http = require("resty.http")
            local etcd = new_cli()
            assert(etcd:set("/ws_watch/seed", "seed"))
            local stale_rev = current_rev(etcd, "/ws_watch/seed")

            -- the global revision moves on while the watched prefix is idle
            for i = 1, 3 do
                assert(etcd:set("/ws_elsewhere/k", "v" .. i))
            end

            -- learn the barrier from a live session, exactly as a watcher would
            local sess = assert(etcd:create_ws_watch_session("/ws_watch",
                                                             {start_revision = stale_rev + 1}))
            assert(sess:recv(2))   -- created ack
            ngx.sleep(0.3)
            assert(sess:request_progress())
            local res = sess:recv(2)
            if not res then
                assert(sess:request_progress())
                res = assert(sess:recv(2))
            end
            local barrier = tonumber(res.result.header.revision)
            sess:close()

            -- compact away every revision below the barrier
            local httpc = http.new()
            local cres = assert(httpc:request_uri("http://127.0.0.1:2379/v3/kv/compaction", {
                method = "POST",
                body = cjson.encode({revision = tostring(barrier), physical = true}),
            }))
            ngx.say("compacted: ", cres.status == 200)

            -- resuming from the barrier is legal: created ack, no compact cancel
            local sess2 = assert(etcd:create_ws_watch_session("/ws_watch",
                                                              {start_revision = barrier + 1}))
            local res2 = assert(sess2:recv(2))
            ngx.say("resume ok: ", res2.result.created == true
                    and res2.result.canceled == nil)

            assert(etcd:set("/ws_watch/after-compact", "z"))
            res2 = assert(sess2:recv(2))
            ngx.say("delivery after compaction: ",
                    res2.result.events[1].kv.key == "/ws_watch/after-compact")
            sess2:close()

            -- control: resuming from the pre-barrier revision must be refused,
            -- which is the expensive resync path the barrier avoids
            local sess3 = assert(etcd:create_ws_watch_session("/ws_watch",
                                                              {start_revision = stale_rev + 1}))
            local canceled = false
            for _ = 1, 3 do
                local res3 = sess3:recv(2)
                if res3 and res3.result.canceled and res3.result.compact_revision then
                    canceled = true
                    break
                end
            end
            ngx.say("stale revision compact-canceled: ", canceled)
            sess3:close()
        }
    }
--- request
GET /t
--- response_body
compacted: true
resume ok: true
delivery after compaction: true
stale revision compact-canceled: true
--- no_error_log
[error]



=== TEST 4: an endpoint that cannot upgrade is rejected at session creation
--- http_config eval: $::HttpConfigNoUpgrade
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require("resty.etcd").new({
                protocol = "v3",
                http_host = "http://127.0.0.1:1985",
                timeout = 2,
            })
            if not etcd then
                ngx.say("failed to new etcd: ", err)
                return
            end

            local sess, err = etcd:create_ws_watch_session("/ws_watch", {})
            ngx.say("session refused: ", sess == nil, ", err: ", err ~= nil)
        }
    }
--- request
GET /t
--- response_body
session refused: true, err: true
--- no_error_log
[error]
