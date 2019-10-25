-- https://github.com/ledgetech/lua-resty-http
local http          = require("resty.http")
local clear_tab     = require("table.clear")
local split         = require("ngx.re").split
local concat_tab    = table.concat
local tostring      = tostring
local select        = select
local ipairs        = ipairs


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


local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local function log_error(...)
    return ngx_log(ngx_ERR, ...)
end
_M.log_error = log_error


local function log_info( ... )
    return ngx_log(ngx_INFO, ...)
end
_M.log_info = log_info


return _M
