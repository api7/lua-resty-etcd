local ngx_shared    = ngx.shared
--local utils         = require("resty.etcd.utils")
local checker

local _M = {}

local function is_healthy(etcd_host)
    ngx.log(ngx.WARN, "etcd_host: ", require("resty.inspect")(etcd_host))
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
    ngx.log(ngx.WARN, "report_fault: ", require("resty.inspect")("report_fault"))

    if checker == nil then
        return
    end

    ngx.log(ngx.WARN, "etcd_host: ", require("resty.inspect")(etcd_host))
    local fails, err = fault_count(etcd_host, checker.shm_name, checker.fail_timeout)
    if err then
        utils.log_error("failed to incr etcd endpoint fail times: ", err)
        return
    end
    ngx.log(ngx.WARN, "fails: ", require("resty.inspect")(fails))

    if fails >= checker.max_fails then
        ngx.log(ngx.WARN, "fails: ", require("resty.inspect")(fails))
    end


end
_M.report_fault = report_fault


function _M.new(opts)
    if checker == nil then
        checker = {}
        local shared_dict = ngx_shared[opts.shm_name]
        if not shared_dict then
            return nil, "failed to get ngx.shared dict: " .. opts.shm_name
        end
        checker.shm_name = opts.shm_name
        checker.fail_timeout = opts.fail_timeout or 10    -- 10 sec
        checker.max_fails = opts.max_fails or 1
        _M.checker = checker
        return _M, nil
    end
end
return _M