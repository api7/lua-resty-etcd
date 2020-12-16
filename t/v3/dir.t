use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);

my $etcd_version = `etcd --version`;
if ($etcd_version =~ /^etcd Version: 2/ || $etcd_version =~ /^etcd Version: 3.1./) {
    plan(skip_all => "etcd is too old, skip v3 protocol");
}
else {
    plan 'no_plan';
}

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/local/share/lua/5.3/?.lua;/usr/share/lua/5.1/?.lua;;';
    init_by_lua_block {
        function check_res(data, err, val, err_msg)
            if err then
                ngx.say("err: ", err)
                ngx.exit(200)
            end

             if val then
                if data and data.body.kvs==nil then
                    ngx.exit(404)
                end

                if data then
                    ngx.log(ngx.NOTICE, "ks length is: ", #(data.body.kvs))
                    ngx.log(ngx.NOTICE, "kv[1] is: ", data.body.kvs[1].value)
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

            if err_msg then
                if err_msg ~= data.body.message then
                    ngx.say("failed to check error msg, got:",
                            data.body.message, ", expect: ", val)
                    ngx.exit(200)
                else
                    ngx.say("checked error msg as expect: ", err_msg)
                end
            end
        end
    }
_EOC_

run_tests();

__DATA__

=== TEST 1: set + readdir + readdir with range_start + rmdir
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local tab_nkeys     = require "table.nkeys"
            local etcd, err = require "resty.etcd" .new({protocol = "v3"})
            check_res(etcd, err)

            local res, err = etcd:rmdir("/dir")
            check_res(res, err)

            local res, err = etcd:set("/dir", "test")
            check_res(res, err)
            local res, err = etcd:set("/dir/a", "a")
            check_res(res, err)
            local res, err = etcd:set("/dir/b", "b")
            check_res(res, err)
            local res, err = etcd:set("/dir/c", "c")
            check_res(res, err)

            res, err = etcd:readdir("/dir", {limit = 3})
            if tab_nkeys(res.body.kvs) == 3 then
                ngx.say("ok")
            else
                ngx.say("failed")
            end

            res, err = etcd:readdir("/dir", {range_start = "/dir/b"})
            check_res(res, err, "b")
            if tab_nkeys(res.body.kvs) == 2 then
                ngx.say("ok")
            else
                ngx.say("failed")
            end

            local res, err = etcd:rmdir("/dir")
            check_res(res, err)
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
ok
checked val as expect: b
ok
