local etcdv3  = require("resty.etcd.v3")
local typeof  = require("typeof")

local _M = {version = 0.9}


function _M.new(opts)
    opts = opts or {}
    if not typeof.table(opts) then
        return nil, 'opts must be table'
    end

    local protocol = opts and opts.protocol or "v3"
    if protocol ~= "v3" then
        return nil, 'only support etcd v3 api'
    end

    opts.timeout = opts.timeout or 5    -- 5 sec
    opts.http_host = opts.http_host or "http://127.0.0.1:2379"
    opts.ttl  = opts.ttl or -1

    local serializer_name = typeof.string(opts.serializer) and opts.serializer
    opts.serializer = serializer_name
    opts.api_prefix = "/v3"

    return etcdv3.new(opts)
end


return _M
