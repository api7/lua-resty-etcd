use Test::Nginx::Socket::Lua 'no_plan';

log_level('info');
repeat_each(1);

my $lua_path = `lua -e 'print(package.path)'`;

our $HttpConfig = <<_EOC_;
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;$lua_path;;';
    init_by_lua_block {
        function check_res(data, err)
            if err then
                ngx.say("err: ", err)
                ngx.exit(200)
            end
        end
    }
_EOC_

run_tests();

__DATA__

=== TEST 1: version
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:version()
            check_res(res, err)

            ngx.say(res.body.etcdserver)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body_like eval
qr{\d+.\d+.\d+}
