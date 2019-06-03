use Test::Nginx::Socket::Lua 'no_plan';

log_level('warn');
repeat_each(2);

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
_EOC_

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local normalize = require "resty.etcd" .normalize

            local function ifNotEqual(l, r)
                if l ~= r then
                    ngx.say("the left and right values were different.")
                end
            end

            ifNotEqual(normalize(), '/')
            ifNotEqual(normalize(nil, '/', 'test', nil, 'test'), '/test/test')

            ifNotEqual(normalize('/path/to/dir/file'), '/path/to/dir/file')
            ifNotEqual(normalize('path', 'to', 'dir', 'file'), '/path/to/dir/file')

            ifNotEqual(normalize('..//path/to/dir/file'), '/path/to/dir/file')
            ifNotEqual(normalize('..', '//path/to/dir/file'), '/path/to/dir/file')

            ifNotEqual(normalize('/path/to/dir/file/../../'), '/path/to')
            ifNotEqual(normalize('/path/to/dir/file/', '..', '..'), '/path/to')

            ifNotEqual(normalize('/path/../to/dir/file'), '/to/dir/file')
            ifNotEqual(normalize('path', '../to', '/dir/file'), '/to/dir/file')

            ifNotEqual(normalize('/path/../to/dir/../../../file'), '/file')
            ifNotEqual(normalize('path', '..', 'to', 'dir', '..', '..', '..', 'file'), '/file')

            ngx.say("all done")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
all done
