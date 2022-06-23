local etcdv3  = require("resty.etcd.v3")
local utils   = require("resty.etcd.utils")
local typeof  = require("typeof")
local require = require
local pcall   = pcall
local decode_json = require("cjson.safe").decode
local http = require("resty.http")
local prefix_v3 = {
    ["3.5."] = "/v3",
    ["3.4."] = "/v3",
    ["3.3."] = "/v3beta",
    ["3.2."] = "/v3alpha",
}

local _M = {version = 0.9}


local function version(self, uri, timeout)
    local http_cli, err = http.new()
    if err then
        return nil, err
    end

    if timeout then
        http_cli:set_timeout(timeout * 1000)
    end

    local headers = {
        ['Content-Type'] = "application/x-www-form-urlencoded",
    }

    local res
    res, err = http_cli:request_uri(uri, {
        method = 'GET',
        headers = headers,
        ssl_verify = self.ssl_verify,
    })

    if err then
        return nil, err
    end

    if res.status >= 500 then
        return nil, "invalid response code: " .. res.status
    end

    if res.status == 401 then
        return nil, "insufficient credentials code: " .. res.status
    end

    if not typeof.string(res.body) then
        return res
    end

    res.body = decode_json(res.body)
    return res
end


local function etcd_version(opts)
    local uri = opts.http_host .. "/version"
    local ver, err = version(opts, uri, opts.timeout)
    if not ver then
        return nil, err
    end

    return ver.body
end

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

    if not opts.api_prefix or not utils.has_value(prefix_v3, opts.api_prefix) then
        local ver, err = etcd_version(opts)
        if not ver then
            return nil, err
        end
        local sub_ver = ver.etcdserver:sub(1, 4)
        opts.api_prefix = prefix_v3[sub_ver] or "/v3beta"
    end

    return etcdv3.new(opts)
end


return _M
