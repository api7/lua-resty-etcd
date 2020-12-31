local ngx_shared  = ngx.shared

local _M = {}

local mt = { __index = _M }

function _M.new(opts)
    local shared_dict = ngx_shared[opts.shm_name]
    if not shared_dict then
        return nil, "failed to get ngx.shared dict: " .. opts.shm_name
    end
    opts.fail_timeout = opts.fail_timeout or 10    -- 10 sec
    opts.max_fails = opts.max_fails or 1
    return setmetatable({
        shm_name     = opts.shm_name,
        fail_timeout = opts.fail_timeout,
        max_fails    = opts.max_fails,
    },
    mt)
end
return _M