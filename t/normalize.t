# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

our $HttpConfig = <<'_EOC_';
    lua_package_path 'lib/?.lua;;';
_EOC_

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local normalize = require "resty.etcd.path" .normalize

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
