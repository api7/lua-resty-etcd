local ngx_shared    = ngx.shared
local utils         = require("resty.etcd.utils")
local conf

local _M = {}

local function gen_unhealthy_key(etcd_host)
    return "unhealthy-" .. etcd_host
end

local function is_healthy(etcd_host)
    if conf == nil then
        return
    end

    local unhealthy_key = gen_unhealthy_key(etcd_host)
    local unhealthy_endpoint, err = ngx_shared[conf.shm_name]:get(unhealthy_key)
    if err then
        utils.log_warn("failed to get unhealthy_key: ",
                unhealthy_key, " err: ", err)
        return
    end

    if not unhealthy_endpoint then
        return true
    end

    return false
end
_M.is_healthy = is_healthy


local function fault_count(key, shm_name, fail_timeout)
    local new_value, err, forcible = ngx_shared[shm_name]:incr(key, 1, 0, fail_timeout)
    if err then
        return nil, err
    end

    if forcible then
        utils.log_warn("shared dict: ", shm_name, " is full, valid items forcibly overwritten")
    end
    return new_value, nil
end


local function report_fault(etcd_host)
    if conf == nil then
        return
    end

    local fails, err = fault_count(etcd_host, conf.shm_name, conf.fail_timeout)
    if err then
        utils.log_error("failed to incr etcd endpoint fail times: ", err)
        return
    end

    if fails >= conf.max_fails then
        local unhealthy_key = gen_unhealthy_key(etcd_host)
        local unhealthy_endpoint, _ = ngx_shared[conf.shm_name]:get(unhealthy_key)
        if unhealthy_endpoint == nil then
            ngx_shared[conf.shm_name]:set(unhealthy_key, etcd_host,
                    conf.fail_timeout)
            utils.log_warn("update endpoint: ", etcd_host, " to unhealthy")
        end
    end
end
_M.report_fault = report_fault


function _M.new(opts)
    if conf == nil then
        conf = {}
        local shared_dict = ngx_shared[opts.shm_name]
        if not shared_dict then
            return nil, "failed to get ngx.shared dict: " .. opts.shm_name
        end
        conf.shm_name = opts.shm_name
        conf.fail_timeout = opts.fail_timeout or 10    -- 10 sec
        conf.max_fails = opts.max_fails or 1
        _M.conf = conf
        return _M, nil
    end
end

return _M