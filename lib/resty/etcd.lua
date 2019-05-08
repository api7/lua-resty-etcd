-- https://github.com/ledgetech/lua-resty-http
local HttpCli = require "resty.http"
local normalize = require "resty.etcd.path"
local typeof = require "resty.etcd.typeof"
local encode_args = ngx.encode_args
local setmetatable = setmetatable
local decode_json, encode_json
do
    local cjson = require "cjson.safe"
    decode_json = cjson.decode
    encode_json = cjson.encode
end
local clear_tab = require "table.clear"
local tab_nkeys = require "table.nkeys"

local _M = {}
local mt = { __index = _M }


function _M.new(opts)
    if opts == nil then
        opts = {}

    elseif not typeof.table(opts) then
        return nil, 'opts must be table'
    end

    local timeout = opts.timeout or 5000    -- 5 sec
    local http_host = opts.host or "http://127.0.0.1:2379"
    local ttl = opts.ttl or -1
    local prefix = opts.prefix or "/v2/keys"

    if not typeof.uint(timeout) then
        return nil, 'opts.timeout must be unsigned integer'
    end

    if not typeof.string(http_host) then
        return nil, 'opts.host must be string'
    end

    if not typeof.int(ttl) then
        return nil, 'opts.ttl must be integer'
    end

    if not typeof.string(prefix) then
        return nil, 'opts.prefix must be string'
    end

    return setmetatable({
            timeout = timeout,
            ttl = ttl,
            endpoints = {
                full_prefix = http_host .. normalize(prefix),
                http_host = http_host,
                prefix = prefix,
                version     = http_host .. '/version',
                statsLeader = http_host .. '/v2/stats/leader',
                statsSelf   = http_host .. '/v2/stats/self',
                statsStore  = http_host .. '/v2/stats/store',
                keys        = http_host .. '/v2/keys',
            }
        },  mt)
end

    local content_type = {
        ["Content-Type"] = "application/x-www-form-urlencoded",
    }


local function _request(method, uri, opts, timeout)
    local body
    if opts and opts.body and tab_nkeys(opts.body) > 0 then
        body = encode_args(opts.body)
    end

    if opts and opts.query and tab_nkeys(opts.query) > 0 then
        uri = uri .. '?' .. encode_args(opts.query)
    end

    local http_cli, err = HttpCli.new()
    if err then
        return nil, err
    end

    if timeout then
        http_cli:set_timeout(timeout * 1000)
    end

    local res, err = http_cli:request_uri(uri, {
        method = method,
        body = body,
        headers = content_type,
    })

    if err then
        return nil, err
    end

    ngx.log(ngx.WARN, "method: ", method)
    ngx.log(ngx.WARN, "uri: ", uri)
    ngx.log(ngx.WARN, "body: ", body)

    if res.status >= 500 then
        return nil, "invalid response code: " .. res.status
    end

    if not typeof.string(res.body) then
        return res
    end

    res.body = decode_json(res.body)
    return res
end


local function set(self, key, val, attr)
    local err
    if val ~= nil and type(val) ~= "number" then
        val, err = encode_json(val)
        if not val then
            return nil, err
        end
    end

    local prevExist
    if attr.prevExist ~= nil then
        prevExist = attr.prevExist and 'true' or 'false'
    end

    local dir
    if attr.dir then
        dir = attr.dir and 'true' or 'false'
    end

    local opts = {
        body = {
            ttl = attr.ttl,
            value = val,
            dir = dir,
        },
        query = {
            prevExist = prevExist,
            prevIndex = attr.prevIndex,
        }
    }
    -- ngx.log(ngx.WARN, require("cjson").encode(opts))

    -- todo: check arguments

    -- verify key
    key = normalize(key)
    if key == '/' then
        return nil, "key should not be a slash"
    end

    local res, err = _request(attr.inOrder and 'POST' or 'PUT',
                              self.endpoints.full_prefix .. key,
                              opts, self.timeout)
    if err then
        return nil, err
    end

    -- get
    if res.status < 300 and res.body.node and
           not res.body.node.dir then
        res.body.node.value, err = decode_json(res.body.node.value)
        if err then
            return nil, err
        end
    end

    return res
end


local function get(self, key, attr)
    local opts
    if attr then
        local attr_wait
        if attr.wait ~= nil then
            attr_wait = attr.wait and 'true' or 'false'
        end

        local attr_recursive
        if attr.recursive then
            attr_recursive = attr.recursive and 'true' or 'false'
        end

        opts = {
            query = {
                wait = attr_wait,
                waitIndex = attr.waitIndex,
                recursive = attr_recursive,
                consistent = attr.consistent,   -- todo
            }
        }
    end

    local res, err = _request("GET",
                              self.endpoints.full_prefix .. normalize(key),
                              opts, attr and attr.timeout or self.timeout)
    if err then
        return nil, err
    end

    -- readdir
    if attr and attr.dir then
        -- set 404 not found if result node is not directory
        if res.status == 200 and res.body.node and
           not res.body.node.dir then
            res.status = 404
            res.body.node.dir = false
        end

        if res.body.node.dir then
            for _, node in ipairs(res.body.node.nodes) do
                node.value, err = decode_json(node.value)
                if err then
                    return nil, err
                end
            end
        else
            res.body.node.value, err = decode_json(res.body.node.value)
            if err then
                return nil, err
            end
        end

        ngx.log(ngx.WARN, "read addr: ", encode_json(res.body.node))

    -- get
    elseif res.status == 200 and res.body.node and
           not res.body.node.dir then
        res.body.node.value, err = decode_json(res.body.node.value)
        if err then
            return nil, err
        end
    end

    return res
end


local function delete(self, key, attr)
    local val, err = attr.prevValue
    if val ~= nil and type(val) ~= "number" then
        val, err = encode_json(val)
        if not val then
            return nil, err
        end
    end

    local attr_dir
    if attr.dir then
        attr_dir = attr.dir and 'true' or 'false'
    end

    local attr_recursive
    if attr.recursive then
        attr_recursive = attr.recursive and 'true' or 'false'
    end

    local opts = {
        query = {
            dir = attr_dir,
            prevIndex = attr.prevIndex,
            recursive = attr_recursive,
            prevValue = val,
        },
    }

    -- todo: check arguments

    return _request("DELETE",
                    self.endpoints.full_prefix .. normalize(key),
                    opts, self.timeout)
end

do

function _M.get(self, key)
    if not typeof.string(key) then
        return nil, 'key must be string'
    end

    return get(self, key)
end

    local attr = {}
function _M.wait(self, key, modifiedIndex, timeout)
    clear_tab(attr)
    attr.wait = true
    attr.waitIndex = modifiedIndex
    attr.timeout = timeout

    return get(self, key, attr)
end

function _M.readdir(self, key, recursive)
    clear_tab(attr)
    attr.dir = true
    attr.recursive = recursive

    return get(self, key, attr)
end

-- wait with recursive
function _M.waitdir(self, key, modifiedIndex, timeout)
    clear_tab(attr)
    attr.wait = true
    attr.dir = true
    attr.recursive = true
    attr.waitIndex = modifiedIndex
    attr.timeout = timeout

    return get(self, key, attr)
end

-- /version
function _M.version(self)
    return _request('GET', self.endpoints.version, nil, self.timeout)
end

-- /stats
function _M.statsLeader(self)
    return _request('GET', self.endpoints.statsLeader, nil, self.timeout)
end

function _M.statsSelf(self)
    return _request('GET', self.endpoints.statsSelf, nil, self.timeout)
end

function _M.statsStore(self)
    return _request('GET', self.endpoints.statsStore, nil, self.timeout)
end

end -- do


do
    local attr = {}
function _M.set(self, key, val, ttl)
    clear_tab(attr)
    attr.ttl = ttl

    return set(self, key, val, attr)
end

-- set key-val and ttl if key does not exists (atomic create)
function _M.setnx(self, key, val, ttl)
    clear_tab(attr)
    attr.ttl = ttl
    attr.prevExist = false

    return set(self, key, val, attr)
end

-- set key-val and ttl if key is exists (update)
function _M.setx(self, key, val, ttl, modifiedIndex)
    clear_tab(attr)
    attr.ttl = ttl
    attr.prevExist = true
    attr.prevIndex = modifiedIndex

    return set(self, key, val, attr)
end

-- dir
function _M.mkdir(self, key, ttl)
    clear_tab(attr)
    attr.ttl = ttl
    attr.dir = true

    return set(self, key, nil, attr)
end

-- mkdir if not exists
function _M.mkdirnx(self, key, ttl)
    clear_tab(attr)
    attr.ttl = ttl
    attr.dir = true
    attr.prevExist = false

    return set(self, key, nil, attr)
end

-- in-order keys
function _M.push(self, key, val, ttl)
    clear_tab(attr)
    attr.ttl = ttl
    attr.inOrder = true

    return set(self, key, val, attr)
end

end -- do


do
    local attr = {}
function _M.delete(self, key, prevVal, modifiedIndex)
    clear_tab(attr)
    attr.prevValue = prevVal
    attr.prevIndex = premodifiedIndexvVal

    return delete(self, key, attr)
end

function _M.rmdir(self, key, recursive)
    clear_tab(attr)
    attr.dir = true
    attr.recursive = recursive

    return delete(self, key, attr)
end

end -- do


return _M
