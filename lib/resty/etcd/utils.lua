-- https://github.com/ledgetech/lua-resty-http
local http          = require("resty.http")
local typeof        = require("typeof")
local encode_args   = ngx.encode_args
local clear_tab     = require "table.clear"
local tab_nkeys     = require "table.nkeys"
local split         = require "ngx.re" .split
local concat_tab    = table.concat
local tostring      = tostring
local select        = select
local ipairs        = ipairs


local _M = {}


local content_type = {
    ["Content-Type"] = "application/x-www-form-urlencoded",
}

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
local ngx_ERR = ngx.INFO
local function log_error(...)
    return ngx_log(ngx_ERR, ...)
end

_M.log_error = log_error


local function request_uri(self, method, uri, opts, timeout)
    local body
    if opts and opts.body and tab_nkeys(opts.body) > 0 then
        body = self.encode_json(opts.body) --encode_args(opts.body)
    end

    if opts and opts.query and tab_nkeys(opts.query) > 0 then
        uri = uri .. '?' .. encode_args(opts.query)
    end

    local http_cli, err = http.new()
    if err then
        return nil, err
    end

    if timeout then
        http_cli:set_timeout(timeout * 1000)
    end

    log_error('uri:', uri, ' body:', body)

    local res
    res, err = http_cli:request_uri(uri, {
        method = method,
        body = body,
        headers = content_type,
    })

    if err then
        return nil, err
    end

    log_error('res body:', res.body, 'status:', res.status)

    if res.status >= 500 then
        return nil, "invalid response code: " .. res.status
    end

    if not typeof.string(res.body) then
        return res
    end

    res.body = self.decode_json(res.body)
    return res
end

_M.request_uri = request_uri


local function request(self, method, host, port, path, opts)
    local body
    if opts and opts.body and tab_nkeys(opts.body) > 0 then
        body = self.encode_json(opts.body) --encode_args(opts.body)
    end

    if opts and opts.query and tab_nkeys(opts.query) > 0 then
        query = encode_args(opts.query)
    end

    local http_cli, err = http.new()
    if err then
        return nil, err
    end


    httpc:connect(host, port)


    local res
    res, err = http_cli:request({
        method = method,
        path   = path,
        body   = body,
        query  = query,
    })

    if err then
        return nil, err
    end

    if res.status >= 500 then
        return nil, "invalid response code: " .. res.status
    end

    if not typeof.string(res.body) then
        return res
    end

    res.body = self.decode_json(res.body)
    return res
end

_M.request = request



return _M