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

    $block->set_value("request", "GET /t");
    $block->set_value("no_error_log", "[error]");

    my $http_config = <<_EOC_;
    lua_package_path 'lib/?.lua;;';
_EOC_
    $block->set_value("http_config", $http_config);

    $block;
});

run_tests();

__DATA__

=== TEST 1: http_host
--- config
    location /t {
        content_by_lua_block {
            local cases = {
                "http://127.0.0.1:2973",
                "http://127.0.0.1",
                "https://127.0.0.1:12000",
                "http://c.cn:9000",
                "http://c-a.cn:9000",
                "http://c_a.cn",
                "http://[ab::0]:2971",
                "http://[ab::0]",
            }
            for _, case in ipairs(cases) do
                local etcd, err = require "resty.etcd" .new({protocol = "v3", api_prefix = "/v3",
                    http_host = case})
                if not etcd then
                    ngx.say(err)
                else
                    ngx.say(
                        etcd.endpoints[1].scheme, " ",
                        etcd.endpoints[1].host, " ",
                        etcd.endpoints[1].port)
                end
            end

            ngx.say('ok')
        }
    }
--- response_body
http 127.0.0.1 2973
http 127.0.0.1 2379
https 127.0.0.1 12000
http c.cn 9000
http c-a.cn 9000
invalid http host: http://c_a.cn, err: not matched
http [ab::0] 2971
http [ab::0] 2379
ok
