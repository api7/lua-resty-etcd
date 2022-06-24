local etcdv3  = require("resty.etcd.v3")
local typeof  = require("typeof")
local require = require
local pcall   = pcall

local _M = {version = 0.9}


local function require_serializer(serializer_name)
    if serializer_name then
        local ok, module = pcall(require, "resty.etcd.serializers." .. serializer_name)
        if ok then
            return module
        end
    end

    return require("resty.etcd.serializers.json")
end

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
    opts.serializer = require_serializer(serializer_name)
    opts.api_prefix = "/v3"

    return etcdv3.new(opts)
end


return _M
