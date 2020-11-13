local ipairs        = ipairs
local pcall         = pcall
local error         = error
local tostring      = tostring
local tonumber      = tonumber
local type          = type
local next          = next
local setmetatable  = setmetatable
local getmetatable  = getmetatable
local ngx_shared    = ngx.shared
local healthcheck
local checker

local headthcheck_endpoint = {
    ["/v3"] = "/health",
    ["/v3beta"] = "/health",
}


local fixed_field_metatable = {
    __index =
    function(t, k)
        error("field " .. tostring(k) .. " does not exist", 3)
    end,
    __newindex =
    function(t, k, v)
        error("attempt to create new field " .. tostring(k), 3)
    end,
}


local function tbl_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[tbl_copy(orig_key)] = tbl_copy(orig_value)
        end
        setmetatable(copy, tbl_copy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end


local function tbl_copy_merge_defaults(t1, defaults)
    if t1 == nil then t1 = {} end
    if defaults == nil then defaults = {} end
    if type(t1) == "table" and type(defaults) == "table" then
        local copy = {}
        for t1_key, t1_value in next, t1, nil do
            copy[tbl_copy(t1_key)] = tbl_copy_merge_defaults(
                    t1_value, tbl_copy(defaults[t1_key])
            )
        end
        for defaults_key, defaults_value in next, defaults, nil do
            if t1[defaults_key] == nil then
                copy[tbl_copy(defaults_key)] = tbl_copy(defaults_value)
            end
        end
        return copy
    else
        return t1 -- not a table
    end
end

local DEFAULTS = setmetatable({
    active = {
        concurrency = 5,
        timeout = 5,
        http_path = "/health",
        host = "",
        type = "http",
        req_headers = {"User-Agent: curl/7.29.0"},
        https_verify_certificate = false,
        healthy = {
            http_statuses = {200},
            interval = 0,
            successes = 1,
        },
        unhealthy = {
            http_statuses = {500, 501, 503, 502, 504, 505},
            interval = 1,
            http_failures = 1,
            tcp_failures = 1,
            timeouts = 1,
        },
    },
    passive = {
        type = "http",
        healthy = {
            http_statuses = {200, 201},
            successes = 1,
        },
        unhealthy = {
            http_statuses = {500},
            http_failures = 1,
            tcp_failures = 1,
            timeouts = 1,
        },
    },
}, fixed_field_metatable)


local _M = {
    version = 0.1,
}



function _M.report_failure(self, endpoint, osi, err, status)
    if not checker then
        return
    end

    if osi == "tcp" then
        checker:report_tcp_failure(endpoint.host, tonumber(endpoint.port), nil, nil, "active")
        checker:report_tcp_failure(endpoint.host, tonumber(endpoint.port), nil, nil, "passive")
        return
    end

    if osi == "http" then
        if status >= 500 then
            checker:report_http_status(endpoint.host, tonumber(endpoint.port),  nil, status, "active")
            checker:report_http_status(endpoint.host, tonumber(endpoint.port),  nil, status, "passive")
            return
        end
    end

    --checker:report_timeout(endpoint.host, tonumber(endpoint.port),  nil, "active")
end


function _M.fetch_health_nodes(self, endpoints)
    if not checker then
        return nil
    end

    for _, endpoint in ipairs(endpoints) do
        local ok = checker:get_target_status(endpoint.host, tonumber(endpoint.port))
        if ok then
            return endpoint
        end
    end

    error("etcd cluster is unavailable")
    return nil
end


function _M.run(opts, endpoints)
    local shared_dict = ngx_shared[opts.cluster_healthcheck.shm_name]
    if not shared_dict then
        error("failed to get ngx.shared dict when start etcd cluster health check")
        return
    end

    --supported etcd version >= 3.3
    --see https://github.com/etcd-io/etcd/blob/master/Documentation/op-guide/monitoring.md#health-check
    if not headthcheck_endpoint[opts.api_prefix] then
        error("unsupported health check for the etcd version < v3.3.0")
        return
    end

    if not checker then
        local ok, checks = pcall(tbl_copy_merge_defaults, opts.cluster_healthcheck.checks, DEFAULTS)
        if not ok then
            return nil, checks
        end

        if not healthcheck then
            healthcheck = require("resty.healthcheck")
        end

        checker = healthcheck.new({
            name = opts.cluster_healthcheck.name or "etcd-cluster-health-check",
            shm_name = opts.cluster_healthcheck.shm_name,
            checks = checks,
        })

        if #endpoints > 1 then
            for _, endpoint in ipairs(endpoints) do
                local _, err = checker:add_target(endpoint.host, endpoint.port, nil, true)
                if not ok then
                    error("failed to add new health check target: ", endpoint.host, ":",
                            endpoint.port, " err: ", err)
                end
            end
        end

        checker:start()
    end
end

return _M