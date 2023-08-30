use Test::Nginx::Socket::Lua;

log_level('info');
no_long_string();
repeat_each(1);

my $enable_tls = $ENV{ETCD_ENABLE_MTLS};
if (defined($enable_tls) && $enable_tls eq "TRUE") {
    plan 'no_plan';
} else {
    plan(skip_all => "etcd is not capable for mTLS connection");
}

my $http_config = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/share/lua/5.1/?.lua;./deps/share/lua/5.1/?.lua;;';
    lua_package_cpath './deps/lib/lua/5.1/?.so;;';
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

        function new_etcd(ssl_verify, ssl_cert_path, ssl_key_path)
            return require "resty.etcd" .new({
                protocol = "v3",
                api_prefix = "/v3",
                http_host = {
                    "https://127.0.0.1:12379",
                    "https://127.0.0.1:22379",
                    "https://127.0.0.1:32379",
                },
                ssl_verify = ssl_verify,
                ssl_cert_path = ssl_cert_path or "t/certs/mtls_client.crt",
                ssl_key_path = ssl_key_path or "t/certs/mtls_client.key",
            })
        end

        function new_etcd_ssl_content(ssl_verify, ssl_cert, ssl_key)
            return require "resty.etcd" .new({
                protocol = "v3",
                api_prefix = "/v3",
                http_host = {
                    "https://127.0.0.1:12379",
                    "https://127.0.0.1:22379",
                    "https://127.0.0.1:32379",
                },
                ssl_verify = ssl_verify,
                ssl_cert = ssl_cert,
                ssl_key = ssl_key,
            })
        end
    }
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->http_config) {
        $block->set_value("http_config", $http_config);
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests();

__DATA__

=== TEST 1: TLS no verify with TLS content
--- config
    location /t {
        content_by_lua_block {
            local cert = [[-----BEGIN CERTIFICATE-----
MIIDOjCCAiICAwD6zzANBgkqhkiG9w0BAQsFADBnMQswCQYDVQQGEwJjbjESMBAG
A1UECAwJR3VhbmdEb25nMQ8wDQYDVQQHDAZaaHVIYWkxDTALBgNVBAoMBGFwaTcx
DDAKBgNVBAsMA29wczEWMBQGA1UEAwwNY2EuYXBpc2l4LmRldjAeFw0yMDA2MjAx
MzE1MDBaFw0zMDA3MDgxMzE1MDBaMF0xCzAJBgNVBAYTAmNuMRIwEAYDVQQIDAlH
dWFuZ0RvbmcxDTALBgNVBAoMBGFwaTcxDzANBgNVBAcMBlpodUhhaTEaMBgGA1UE
AwwRY2xpZW50LmFwaXNpeC5kZXYwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
AoIBAQCfKI8uiEH/ifZikSnRa3/E2B4ohVWRwjo/IxyDEWomgR4tLk1pSJhP/4SC
LWuMQTFWTbSqt1IFYy4ZbVSHHyGoNPmJGrHRJCGE+sgpfzn0GjV4lXQPJD0k6GR1
CX2Mo1TWdFqSJ/Hc5AQwcQFnPfoLAwsBy4yqrlmf96ZAUytl/7Zkjf4P7mJkJHtM
/WgSR0pGhjZTAGRf5DJWoO51ki3i3JI+15mOhmnnCpnksnGVPfl92q92Hz/4v3iq
E+UThPYRpcGbnddzMvPaCXiavg8B/u2LVbn4l0adamqQGepOAjD/1xraOVP2W22W
0PztDXJ4rLe+capNS4oGuSUfkIENAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAHKn
HxUhuk/nL2Sg5UB84OoJe5XPgNBvVMKN0c/NAPKVIPninvUcG/mHeKexPzE0sMga
RNos75N2199EXydqUcsJ8jL0cNtQ2k5JQXXg0ntNC4tuCgIKAOnO879y5hSG36e5
7wmAoVKnabgjej09zG1kkXvAmpgqoxeVCu7h7fK+AurLbsGCTaHoA5pG1tcHDxJQ
fpVcbBfwQDSBW3SQjiRqX453/01nw6kbOeLKYraJysaG8ZU2K8+WpW6JDubciHjw
fQnpU2U16XKivhxeuKYrV/INL0sxj/fZraNYErvJWzh5llvIdNLmeSPmvb50JUIs
+lDqn1MobTXzDpuCFXA=
-----END CERTIFICATE-----]]
            local pkey = [[-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAnyiPLohB/4n2YpEp0Wt/xNgeKIVVkcI6PyMcgxFqJoEeLS5N
aUiYT/+Egi1rjEExVk20qrdSBWMuGW1Uhx8hqDT5iRqx0SQhhPrIKX859Bo1eJV0
DyQ9JOhkdQl9jKNU1nRakifx3OQEMHEBZz36CwMLAcuMqq5Zn/emQFMrZf+2ZI3+
D+5iZCR7TP1oEkdKRoY2UwBkX+QyVqDudZIt4tySPteZjoZp5wqZ5LJxlT35fdqv
dh8/+L94qhPlE4T2EaXBm53XczLz2gl4mr4PAf7ti1W5+JdGnWpqkBnqTgIw/9ca
2jlT9lttltD87Q1yeKy3vnGqTUuKBrklH5CBDQIDAQABAoIBAHDe5bPdQ9jCcW3z
fpGax/DER5b6//UvpfkSoGy/E+Wcmdb2yEVLC2FoVwOuzF+Z+DA5SU/sVAmoDZBQ
vapZxJeygejeeo5ULkVNSFhNdr8LOzJ54uW+EHK1MFDj2xq61jaEK5sNIvRA7Eui
SJl8FXBrxwmN3gNJRBwzF770fImHUfZt0YU3rWKw5Qin7QnlUzW2KPUltnSEq/xB
kIzyWpuj7iAm9wTjH9Vy06sWCmxj1lzTTXlanjPb1jOTaOhbQMpyaAzRgQN8PZiE
YKCarzVj7BJr7/vZYpnQtQDY12UL5n33BEqMP0VNHVqv+ZO3bktfvlwBru5ZJ7Cf
URLsSc0CgYEAyz7FzV7cZYgjfUFD67MIS1HtVk7SX0UiYCsrGy8zA19tkhe3XVpc
CZSwkjzjdEk0zEwiNAtawrDlR1m2kverbhhCHqXUOHwEpujMBjeJCNUVEh3OABr8
vf2WJ6D1IRh8FA5CYLZP7aZ41fcxAnvIPAEThemLQL3C4H5H5NG2WFsCgYEAyHhP
onpS/Eo/OXKYFLR/mvjizRVSomz1lVVL+GWMUYQsmgsPyBJgyAOX3Pqt9catgxhM
DbEr7EWTxth3YeVzamiJPNVK0HvCax9gQ0KkOmtbrfN54zBHOJ+ieYhsieZLMgjx
iu7Ieo6LDGV39HkvekzutZpypiCpKlMaFlCFiLcCgYEAmAgRsEj4Nh665VPvuZzH
ZIgZMAlwBgHR7/v6l7AbybcVYEXLTNJtrGEEH6/aOL8V9ogwwZuIvb/TEidCkfcf
zg/pTcGf2My0MiJLk47xO6EgzNdso9mMG5ZYPraBBsuo7NupvWxCp7NyCiOJDqGH
K5NmhjInjzsjTghIQRq5+qcCgYEAxnm/NjjvslL8F69p/I3cDJ2/RpaG0sMXvbrO
VWaMryQyWGz9OfNgGIbeMu2Jj90dar6ChcfUmb8lGOi2AZl/VGmc/jqaMKFnElHl
J5JyMFicUzPMiG8DBH+gB71W4Iy+BBKwugHBQP2hkytewQ++PtKuP+RjADEz6vCN
0mv0WS8CgYBnbMRP8wIOLJPRMw/iL9BdMf606X4xbmNn9HWVp2mH9D3D51kDFvls
7y2vEaYkFv3XoYgVN9ZHDUbM/YTUozKjcAcvz0syLQb8wRwKeo+XSmo09+360r18
zRugoE7bPl39WdGWaW3td0qf1r9z3sE2iWUTJPRQ3DYpsLOYIgyKmw==
-----END RSA PRIVATE KEY-----]]
            local etcd, err = new_etcd_ssl_content(false, cert, pkey)
            check_res(etcd, err)

            local res, err = etcd:set("/test", { a='aaa'})
            check_res(res, err)
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 2: TLS no verify
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = new_etcd(false)
            check_res(etcd, err)

            local res, err = etcd:set("/test", { a='abc'})
            check_res(res, err)
            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 3: TLS verify
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = new_etcd(true)
            check_res(etcd, err)

            local res, err = etcd:set("/test", { a='abc'})
            check_res(res, err)
            ngx.say("done")
        }
    }
--- response_body_like
unable to get local issuer certificate



=== TEST 4: watch
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = new_etcd(false)
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
--- response_body_like eval
qr/1:.*"created":true.*
2:.*"value":"bcd3".*
timeout/
--- timeout: 5



=== TEST 5: bad client certificate
--- config
    location /t {
        content_by_lua_block {
            local etcd, err = new_etcd(false, "t/certs/etcd.pem", "t/certs/etcd.key")
            check_res(etcd, err)

            local res, err = etcd:set("/test", { a='abc'})
            check_res(res, err)
            ngx.say("done")
        }
    }
--- error_log
bad certificate
--- response_body_like
handshake failed



=== TEST 6: bad client certificate wtih ssl content
--- config
    location /t {
        content_by_lua_block {
            local cert = [[-----BEGIN CERTIFICATE-----
MIIDrzCCApegAwIBAgIJAI3Meu/gJVTLMA0GCSqGSIb3DQEBCwUAMG4xCzAJBgNV
BAYTAkNOMREwDwYDVQQIDAhaaGVqaWFuZzERMA8GA1UEBwwISGFuZ3pob3UxDTAL
BgNVBAoMBHRlc3QxDTALBgNVBAsMBHRlc3QxGzAZBgNVBAMMEmV0Y2QuY2x1c3Rl
ci5sb2NhbDAeFw0yMDEwMjgwMzMzMDJaFw0yMTEwMjgwMzMzMDJaMG4xCzAJBgNV
BAYTAkNOMREwDwYDVQQIDAhaaGVqaWFuZzERMA8GA1UEBwwISGFuZ3pob3UxDTAL
BgNVBAoMBHRlc3QxDTALBgNVBAsMBHRlc3QxGzAZBgNVBAMMEmV0Y2QuY2x1c3Rl
ci5sb2NhbDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ/qwxCR7g5S
s9+VleopkLi5pAszEkHYOBpwF/hDeRdxU0I0e1zZTdTlwwPy2vf8m3kwoq6fmNCt
tdUUXh5Wvgi/2OA8HBBzaQFQL1Av9qWwyES5cx6p0ZBwIrcXQIsl1XfNSUpQNTSS
D44TGduXUIdeshukPvMvLWLezynf2/WlgVh/haWtDG99r/Gj3uBdjl0m/xGvKvIv
NFy6EdgG9fkwcIalutjrUnGl9moGjwKYu4eXW2Zt5el0d1AHXUsqK4voe0p+U2Nz
quDmvxteXWdlsz8o5kQT6a4DUtWhpPIfNj9oZfPRs3LhBFQ74N70kVxMOCdec1lU
bnFzLIMGlz0CAwEAAaNQME4wHQYDVR0OBBYEFFHeljijrr+SPxlH5fjHRPcC7bv2
MB8GA1UdIwQYMBaAFFHeljijrr+SPxlH5fjHRPcC7bv2MAwGA1UdEwQFMAMBAf8w
DQYJKoZIhvcNAQELBQADggEBAG6NNTK7sl9nJxeewVuogCdMtkcdnx9onGtCOeiQ
qvh5Xwn9akZtoLMVEdceU0ihO4wILlcom3OqHs9WOd6VbgW5a19Thh2toxKidHz5
rAaBMyZsQbFb6+vFshZwoCtOLZI/eIZfUUMFqMXlEPrKru1nSddNdai2+zi5rEnM
HCot43+3XYuqkvWlOjoi9cP+C4epFYrxpykVbcrtbd7TK+wZNiK3xtDPnVzjdNWL
geAEl9xrrk0ss4nO/EreTQgS46gVU+tLC+b23m2dU7dcKZ7RDoiA9bdVc4a2IsaS
2MvLL4NZ2nUh8hAEHiLtGMAV3C6xNbEyM07hEpDW6vk6tqk=
-----END CERTIFICATE-----]]
            local pkey = [[-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCf6sMQke4OUrPf
lZXqKZC4uaQLMxJB2DgacBf4Q3kXcVNCNHtc2U3U5cMD8tr3/Jt5MKKun5jQrbXV
FF4eVr4Iv9jgPBwQc2kBUC9QL/alsMhEuXMeqdGQcCK3F0CLJdV3zUlKUDU0kg+O
Exnbl1CHXrIbpD7zLy1i3s8p39v1pYFYf4WlrQxvfa/xo97gXY5dJv8RryryLzRc
uhHYBvX5MHCGpbrY61JxpfZqBo8CmLuHl1tmbeXpdHdQB11LKiuL6HtKflNjc6rg
5r8bXl1nZbM/KOZEE+muA1LVoaTyHzY/aGXz0bNy4QRUO+De9JFcTDgnXnNZVG5x
cyyDBpc9AgMBAAECggEAatcEtehZPJaCeClPPF/Cwbe9YoIfe4BCk186lHI3z7K1
5nB7zt+bwVY0AUpagv3wvXoB5lrYVOsJpa9y5iAb3GqYMc/XDCKfD/KLea5hwfcn
BctEn0LjsPVKLDrLs2t2gBDWG2EU+udunwQh7XTdp2Nb6V3FdOGbGAg2LgrSwP1g
0r4z14F70oWGYyTQ5N8UGuyryVrzQH525OYl38Yt7R6zJ/44FVi/2TvdfHM5ss39
SXWi00Q30fzaBEf4AdHVwVCRKctwSbrIOyM53kiScFDmBGRblCWOxXbiFV+d3bjX
gf2zxs7QYZrFOzOO7kLtHGua4itEB02497v+1oKDwQKBgQDOBvCVGRe2WpItOLnj
SF8iz7Sm+jJGQz0D9FhWyGPvrN7IXGrsXavA1kKRz22dsU8xdKk0yciOB13Wb5y6
yLsr/fPBjAhPb4h543VHFjpAQcxpsH51DE0b2oYOWMmz+rXGB5Jy8EkP7Q4njIsc
2wLod1dps8OT8zFx1jX3Us6iUQKBgQDGtKkfsvWi3HkwjFTR+/Y0oMz7bSruE5Z8
g0VOHPkSr4XiYgLpQxjbNjq8fwsa/jTt1B57+By4xLpZYD0BTFuf5po+igSZhH8s
QS5XnUnbM7d6Xr/da7ZkhSmUbEaMeHONSIVpYNgtRo4bB9Mh0l1HWdoevw/w5Ryt
L/OQiPhfLQKBgQCh1iG1fPh7bbnVe/HI71iL58xoPbCwMLEFIjMiOFcINirqCG6V
LR91Ytj34JCihl1G4/TmWnsH1hGIGDRtJLCiZeHL70u32kzCMkI1jOhFAWqoutMa
7obDkmwraONIVW/kFp6bWtSJhhTQTD4adI9cPCKWDXdcCHSWj0Xk+U8HgQKBgBng
t1HYhaLzIZlP/U/nh3XtJyTrX7bnuCZ5FhKJNWrYjxAfgY+NXHRYCKg5x2F5j70V
be7pLhxmCnrPTMKZhik56AaTBOxVVBaYWoewhUjV4GRAaK5Wc8d9jB+3RizPFwVk
V3OU2DJ1SNZ+W2HBOsKrEfwFF/dgby6i2w6MuAP1AoGBAIxvxUygeT/6P0fHN22P
zAHFI4v2925wYdb7H//D8DIADyBwv18N6YH8uH7L+USZN7e4p2k8MGGyvTXeC6aX
IeVtU6fH57Ddn59VPbF20m8RCSkmBvSdcbyBmqlZSBE+fKwCliKl6u/GH0BNAWKz
r8yiEiskqRmy7P7MY9hDmEbG
-----END PRIVATE KEY-----]]

            local etcd, err = new_etcd_ssl_content(false, cert, pkey)
            check_res(etcd, err)

            local res, err = etcd:set("/test", { a='abc'})
            check_res(res, err)
            ngx.say("done")
        }
    }
--- error_log
bad certificate
--- response_body_like
handshake failed
