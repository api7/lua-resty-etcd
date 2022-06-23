local etcdv3  = require("resty.etcd.v3")
local utils   = require("resty.etcd.utils")
local typeof  = require("typeof")
local require = require
local pcall   = pcall
local decode_json = require("cjson.safe").decode
local http = require("resty.http")
local ipairs = ipairs
local prefix_v3 = {
    ["3.5."] = "/v3",
    ["3.4."] = "/v3",
    ["3.3."] = "/v3beta",
    ["3.2."] = "/v3alpha",
}

local _M = {version = 0.9}


local function fetch_version(host, timeout, ssl_verify)
    local uri = host .. "/version"
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
        ssl_verify = ssl_verify,
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
    return res.body
end

local function etcd_version(opts)
    if typeof.string(opts.http_host) then
        return fetch_version(opts.http_host, opts.timeout, opts.ssl_verify)
    end

    if typeof.table(opts.http_host) and #opts.http_host == 1 then
        return fetch_version(opts.http_host[1], opts.timeout, opts.ssl_verify)
    end

    if typeof.table(opts.http_host) and #opts.http_host > 1 then
        local err
        for _, host in ipairs(opts.http_host) do
            local ver
            ver, err = fetch_version(host, opts.timeout, opts.ssl_verify)
            if ver then
                return ver
            end
        end
        return nil, err
    end

    return nil, "invalid etcd host format"
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
