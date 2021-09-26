-- https://github.com/api7/lua-resty-http
local http          = require("resty.http")
local clear_tab     = require("table.clear")
local split         = require("ngx.re").split
local find          = ngx.re.find
local concat_tab    = table.concat
local tostring      = tostring
local select        = select
local ipairs        = ipairs
local pairs         = pairs
local type          = type


if not http.tls_handshake then
    error("Bad http library. Should use api7-lua-resty-http instead")
end


local _M = {http = http}

local normalize
do
    local items = {}
    local function concat(sep, ...)
        local argc = select('#', ...)
        clear_tab(items)
        local len = 0

        for i = 1, argc do
            local v = select(i, ...)
            if v ~= nil then
                len = len + 1
                items[len] = tostring(v)
            end
        end

        return concat_tab(items, sep);
    end


    local segs = {}
    function normalize(...)
        local path = concat('/', ...)
        local names = {}
        local err

        segs, err = split(path, [[/]], "jo", nil, nil, segs)
        if not segs then
            return nil, err
        end

        local len = 0
        for _, seg in ipairs(segs) do
            if seg == '..' then
                if len > 0 then
                    len = len - 1
                end

            elseif seg == '' or seg == '/' and names[len] == '/' then
                -- do nothing

            elseif seg ~= '.' then
                len = len + 1
                names[len] = seg
            end
        end

        return '/' .. concat_tab(names, '/', 1, len);
    end
end
_M.normalize = normalize


function _M.get_real_key(prefix, key)
    return (type(prefix) == 'string' and prefix or "") .. key
end


function _M.has_value(arr, val)
    for key, value in pairs(arr) do
        if value == val then
            return key
        end
    end

    return false
end

function _M.starts_with(str, start)
    return str:sub(1, #start) == start
end

local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_WARN = ngx.WARN
local function log_error(...)
    return ngx_log(ngx_ERR, ...)
end
_M.log_error = log_error


local function log_info( ... )
    return ngx_log(ngx_INFO, ...)
end
_M.log_info = log_info


local function log_warn( ... )
    return ngx_log(ngx_WARN, ...)
end
_M.log_warn = log_warn


local function verify_key(key)
    if not key or #key == 0 then
        return false, "key should not be empty"
    end
    return true, nil
end
_M.verify_key = verify_key

local function is_empty_str(input_str)
    return (find(input_str or '', [=[^\s*$]=], "jo"))
end
_M.is_empty_str = is_empty_str

return _M
