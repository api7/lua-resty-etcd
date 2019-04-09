local clear_tab = require "table.clear"
local concat_tab = table.concat
local tostring = tostring
local select = select
local split = require "ngx.re" .split
local ipairs = ipairs


local _M = {}

local normalize
do
    local res = {}
local function concat(sep, ...)
    local argc = select('#', ...)
    clear_tab(res)
    local len = 0

    for i = 1, argc do
        local v = select(i, ...)
        if v ~= nil then
            len = len + 1
            res[len] = tostring(v)
        end
    end

    return concat_tab(res, sep);
end

    local segs = {}
function _M.normalize(...)
    local path = concat('/', ...)
    -- ngx.log(ngx.WARN, "path: ", path)
    local res = {}
    local len = 0

    local segs, err = split(path, [[/]], "jo", nil, nil, segs)
    if not segs then
        return nil, err
    end
    -- ngx.log(ngx.WARN, "segs: ", require("cjson").encode(segs))

    for i,seg in ipairs(segs) do
        if seg == '..' then
            if len > 0 then
                len = len - 1
            end
        
        elseif seg == '' or seg == '/' and res[len] == '/' then
            -- do nothing

        elseif seg ~= '.' then
            len = len + 1
            res[len] = seg
        end
    end

    return '/' .. concat_tab(res, '/', 1, len);
end

end -- do


return _M
