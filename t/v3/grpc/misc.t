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

    my $http_config = <<'_EOC_';
        lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
_EOC_
    if (!$block->http_config) {
        $block->set_value("http_config", $http_config);
    }
});

run_tests();

__DATA__

=== TEST 1: load etcd module in init_by_lua
--- http_config
lua_package_path 'lib/?.lua;;';
init_by_lua_block {
    require("resty.etcd")
}
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = require "resty.etcd" .new({protocol = "v3", use_grpc = true})
            if etcd == nil then
                ngx.say(err)
            end
        }
    }
--- response_body



=== TEST 2: close conn
--- config
    location /t {
        content_by_lua_block {
            local etcd = require "resty.etcd" .new({protocol = "v3", use_grpc = true})
            assert(etcd.conn ~= nil)
            etcd:close()
            assert(etcd.conn == nil)
        }
    }
