use Test::Nginx::Socket::Lua 'no_plan';

log_level('warn');
repeat_each(2);

our $HttpConfig = <<'_EOC_';
    lua_socket_log_errors off;
    lua_package_path 'lib/?.lua;/usr/share/lua/5.1/?.lua;;';
_EOC_

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local typeof = require('resty.etcd.typeof')
            local DEFAULT_CMP = {
                ['nil']         = false,
                ['non']         = false,
                ['boolean']     = false,
                ['string']      = false,
                ['table']       = false,
                ['thread']      = false,
                ['Function']    = false,
                ['number']      = false,
                ['finite']      = false,
                ['unsigned']    = false,
                ['int']         = false,
                ['int8']        = false,
                ['int16']       = false,
                ['int32']       = false,
                ['uint']        = false,
                ['uint8']       = false,
                ['uint16']      = false,
                ['uint32']      = false,
            }
            -- types
            local data = {
                -- nil
                {   chk = {
                        ['nil']     = true,
                        ['non']     = true
                    }
                },

                -- boolean
                {   val = true,
                    chk = {
                        ['boolean'] = true
                    }
                },
                {   val = false,
                    chk = {
                        ['boolean'] = true,
                        ['non']     = true
                    }
                },

                -- string
                {   val = 'hello',
                    chk = {
                        ['string']  = true
                    }
                },
                {   val = 'world',
                    chk = {
                        ['string']  = true
                    }
                },
                {   val = '',
                    chk = {
                        ['string']  = true,
                        ['non']     = true
                    }
                },

                -- number
                {   val = 0,
                    chk = {
                        ['number']      = true,
                        ['finite']      = true,
                        ['unsigned']    = true,
                        ['int']         = true,
                        ['int8']        = true,
                        ['int16']       = true,
                        ['int32']       = true,
                        ['uint']        = true,
                        ['uint8']       = true,
                        ['uint16']      = true,
                        ['uint32']      = true,
                        ['non']         = true
                    }
                },
                {   val = 1,
                    chk = {
                        ['number']      = true,
                        ['finite']      = true,
                        ['unsigned']    = true,
                        ['int']         = true,
                        ['int8']        = true,
                        ['int16']       = true,
                        ['int32']       = true,
                        ['uint']        = true,
                        ['uint8']       = true,
                        ['uint16']      = true,
                        ['uint32']      = true,
                    }
                },
                {   val = -1,
                    chk = {
                        ['number']      = true,
                        ['finite']      = true,
                        ['int']         = true,
                        ['int8']        = true,
                        ['int16']       = true,
                        ['int32']       = true,
                    }
                },
                {   val = 0.1,
                    chk = {
                        ['number']  = true,
                        ['finite']  = true,
                        ['unsigned']= true
                    }
                },
                {   val = -0.1,
                    chk = {
                        ['number']  = true,
                        ['finite']  = true
                    }
                },
                {   val = 1/0,
                    chk = {
                        ['number']  = true
                    }
                },
                {   val = 0/0,
                    chk = {
                        ['number']  = true,
                        ['nan']     = true,
                        ['non']     = true
                    }
                },

                -- integer
                {   val = -128,
                    chk = {
                        ['number']  = true,
                        ['finite']  = true,
                        ['int']     = true,
                        ['int8']    = true,
                        ['int16']   = true,
                        ['int32']   = true
                    }
                },
                {   val = 127,
                    chk = {
                        ['number']  = true,
                        ['finite']  = true,
                        ['unsigned']= true,
                        ['int']     = true,
                        ['int8']    = true,
                        ['int16']   = true,
                        ['int32']   = true,
                        ['uint']    = true,
                        ['uint8']   = true,
                        ['uint16']  = true,
                        ['uint32']  = true,
                    }
                },
                {   val = -32768,
                    chk = {
                        ['number']  = true,
                        ['finite']  = true,
                        ['int']     = true,
                        ['int16']   = true,
                        ['int32']   = true
                    }
                },
                {   val = 32767,
                    chk = {
                        ['number']  = true,
                        ['finite']  = true,
                        ['unsigned']= true,
                        ['int']     = true,
                        ['int16']   = true,
                        ['int32']   = true,
                        ['uint']    = true,
                        ['uint16']  = true,
                        ['uint32']  = true,
                    }
                },
                {   val = -2147483648,
                    chk = {
                        ['number']  = true,
                        ['finite']  = true,
                        ['int']     = true,
                        ['int32']   = true
                    }
                },
                {   val = 2147483647,
                    chk = {
                        ['number']  = true,
                        ['finite']  = true,
                        ['unsigned']= true,
                        ['int']     = true,
                        ['int32']   = true,
                        ['uint']    = true,
                        ['uint32']  = true,
                    }
                },
                -- unsigned integer
                {   val = 255,
                    chk = {
                        ['number']  = true,
                        ['finite']  = true,
                        ['unsigned']= true,
                        ['int']     = true,
                        ['int16']   = true,
                        ['int32']   = true,
                        ['uint']    = true,
                        ['uint8']   = true,
                        ['uint16']  = true,
                        ['uint32']  = true
                    }
                },
                {   val = 65535,
                    chk = {
                        ['number']  = true,
                        ['finite']  = true,
                        ['unsigned']= true,
                        ['int']     = true,
                        ['int32']   = true,
                        ['uint']    = true,
                        ['uint16']  = true,
                        ['uint32']  = true
                    }
                },
                {   val = 4294967295,
                    chk = {
                        ['number']  = true,
                        ['finite']  = true,
                        ['unsigned']= true,
                        ['int']     = true,
                        ['uint']    = true,
                        ['uint32']  = true
                    }
                },

                -- function
                {   val = function()end,
                    chk = {
                        ['Function']= true
                    }
                },

                -- table
                {   val = {},
                    chk = {
                        ['table']   = true
                    }
                },

                -- thread
                {   val = coroutine.create(function() end),
                    chk = {
                        ['thread']  = true
                    }
                }
            }
            local nilVal
            local msg

            for _, field in ipairs(data) do
                for method, res in pairs(DEFAULT_CMP) do
                    if field.chk[method] ~= nil then
                        res = field.chk[method]
                    end
                    msg = ('typeof.%s(%s) == %s'):format(
                        method, tostring(field.val), tostring(res)
                    )
                    if typeof[method](field.val) ~= res then
                        ngx.say(msg)
                    end
                end
            end
            ngx.say("all done")
        }
    }
--- request
GET /t
--- no_error_log
[error]
--- response_body
all done
