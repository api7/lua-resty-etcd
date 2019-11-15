local etcdv2 = require("resty.etcd.v2")
local etcdv3 = require("resty.etcd.v3")
local typeof = require("typeof")
local prefix_v3 = {
    ["3.5."] = "/v3",
    ["3.4."] = "/v3",
    ["3.3."] = "/v3beta",
    ["3.2."] = "/v3alpha",
}

local _M = {version = 0.9}


local function etcd_version(opts)
    local etcd_obj, err = etcdv2.new(opts)
    if not etcd_obj then
        return nil, err
    end

    local ver
    ver, err = etcd_obj:version()
    if not ver then
        return nil, err
    end

    return ver.body
end


function _M.new(opts)
    opts = opts or {}
    if not typeof.table(opts) then
        return nil, 'opts must be table'
    end

    if opts.host and not typeof.string(opts.host) then
        return nil, 'opts.host must be string'
    end

    if opts.port and not typeof.int(opts.port) then
        return nil, 'opts.port must be integer'
    end

    opts.timeout = opts.timeout or 5    -- 5 sec
    opts.http_host = opts.http_host or "http://" .. (opts.host or "127.0.0.1")
                                       .. ":" .. (opts.port or 2379)
    opts.ttl  = opts.ttl or -1

    local protocol = opts and opts.protocol or "v2"
    if protocol == "v3" then

        local etcd_prefix = opts.etcd_prefix
        -- if opts special the etcd_prefix,no need to check version
        if not etcd_prefix then
            local ver, err = etcd_version(opts)
            if not ver then
                return nil, err
            end
            local sub_ver = ver.etcdserver:sub(1, 4)
            etcd_prefix = prefix_v3[sub_ver] or "/v3beta"
        end
        opts.api_prefix = etcd_prefix .. (opts.api_prefix or "")
        return etcdv3.new(opts)
    end

    return etcdv2.new(opts)
end


return _M
