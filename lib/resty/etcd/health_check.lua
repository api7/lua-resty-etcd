local ngx_shared    = ngx.shared
local utils         = require("resty.etcd.utils")
local type          = type
local now           = os.time
local conf

local HEALTH_CHECK_MODE_ROUND_ROBIN = "round-robin"
local HEALTH_CHECK_MODE_SHARED_DICT = "shared-dict"
local HEALTH_CHECK_MODE_DISABLED = "disabled"

local _M = {}
_M.ROUND_ROBIN_MODE = HEALTH_CHECK_MODE_ROUND_ROBIN
_M.SHARED_DICT_MODE = HEALTH_CHECK_MODE_SHARED_DICT
_M.DISABLED_MODE = HEALTH_CHECK_MODE_DISABLED

local round_robin_unhealthy_target_hosts


local function gen_unhealthy_key(etcd_host)
    return "unhealthy-" .. etcd_host
end

local function get_target_status(etcd_host)
    if not conf then
        return nil, "etcd health check uninitialized"
    end

    if conf.disabled then
        return true
    end

    if type(etcd_host) ~= "string" then
        return false, "etcd host invalid"
    end

    local unhealthy_key = gen_unhealthy_key(etcd_host)
    if conf.shm_name ~= nil then
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
    else
        if type(round_robin_unhealthy_target_hosts) ~= "table" then
            round_robin_unhealthy_target_hosts = {}
        end

        local target_fail_expired_time = round_robin_unhealthy_target_hosts[unhealthy_key]
        if target_fail_expired_time and target_fail_expired_time >= now() then
            return false, "endpoint: " .. etcd_host .. " is unhealthy"
        else
            return true
        end
    end
end
_M.get_target_status = get_target_status


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


local function report_failure(etcd_host)
    if not conf then
        return nil, "etcd health check uninitialized"
    end

    if conf.disabled then
        return
    end

    if type(etcd_host) ~= "string" then
        return nil, "etcd host invalid"
    end

    if conf.shm_name ~= nil then
        local fails, err = fault_count(etcd_host, conf.shm_name, conf.fail_timeout)
        if err then
            utils.log_error("failed to incr etcd endpoint fail times: ", err)
            return nil, err
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
    else
        if type(round_robin_unhealthy_target_hosts) ~= "table" then
            round_robin_unhealthy_target_hosts = {}
        end
        local unhealthy_key = gen_unhealthy_key(etcd_host)
        round_robin_unhealthy_target_hosts[unhealthy_key] = now() + conf.fail_timeout
        utils.log_warn("update endpoint: ", etcd_host, " to unhealthy")
    end
end
_M.report_failure = report_failure


local function get_check_mode()
    -- round-robin: nginx worker memory round-robin based health check
    -- shared-dict: nginx shared memory policy based health check
    if conf then
        if conf.disabled then
            return HEALTH_CHECK_MODE_DISABLED
        elseif conf.shm_name then
            return HEALTH_CHECK_MODE_SHARED_DICT
        end
    end

    return HEALTH_CHECK_MODE_ROUND_ROBIN
end
_M.get_check_mode = get_check_mode


function _M.disable()
    if not conf then
        conf = {}
    end

    conf.disabled = true
    _M.conf = conf
end


function _M.init(opts)
    opts = opts or {}
    if not conf or opts.shm_name ~= conf.shm_name then
        conf = {}
        if opts.shm_name and type(opts.shm_name) == "string" then
            local shared_dict = ngx_shared[opts.shm_name]
            if not shared_dict then
                return nil, "failed to get ngx.shared dict: " .. opts.shm_name
            end
            conf.shm_name = opts.shm_name
            utils.log_info("healthy check use ngx.shared dict: ", opts.shm_name)
        else
            utils.log_info("healthy check use round robin")
        end
        conf.fail_timeout = opts.fail_timeout or 10    -- 10 sec
        conf.max_fails = opts.max_fails or 1
        conf.retry = opts.retry or false
        _M.conf = conf
        return _M, nil
    end
end

return _M
