-- https://github.com/ledgetech/lua-resty-http
local http          = require("resty.http")
local typeof        = require("typeof")
local cjson         = require("cjson.safe")
local encode_args   = ngx.encode_args
local setmetatable  = setmetatable
local clear_tab     = require("table.clear")
local ipairs        = ipairs
local type          = type
local utils         = require("resty.etcd.utils")
local encode_base64 = ngx.encode_base64
local require       = require
local next          = next
local table         = table
local decode_json   = cjson.decode
local INIT_COUNT_RESIZE = 2e8


local _M = {}


local mt = { __index = _M }


local table_exist_keys
local tb_nkeys
local _, perr = pcall(function()
    tb_nkeys = require "table.nkeys"
end)
if tb_nkeys and not perr then
    table_exist_keys = function(t)
        return tb_nkeys(t) > 0
    end
else
    table_exist_keys = function(t)
        return next(t)
    end
end


function _M.new(opts)
    local timeout = opts.timeout
    local ttl = opts.ttl
    local api_prefix = opts.api_prefix or ""
    local key_prefix = opts.key_prefix or ""
    local http_host = opts.http_host
    local user = opts.user
    local password = opts.password
    local serializer = opts.serializer
    local ssl_verify = opts.ssl_verify

    if not typeof.uint(timeout) then
        return nil, 'opts.timeout must be unsigned integer'
    end

    if not typeof.string(http_host) and not typeof.table(http_host) then
        return nil, 'opts.http_host must be string or string array'
    end

    if not typeof.int(ttl) then
        return nil, 'opts.ttl must be integer'
    end

    if not typeof.string(api_prefix) then
        return nil, 'opts.api_prefix must be string'
    end

    if not typeof.string(key_prefix) then
        return nil, 'opts.key_prefix must be string'
    end

    if user and not typeof.string(user) then
        return nil, 'opts.user must be string or ignore'
    end

    if password and not typeof.string(password) then
        return nil, 'opts.password must be string or ignore'
    end

    local endpoints = {}
    local http_hosts
    if type(http_host) == 'string' then -- signle node
        http_hosts = {http_host}
    else
        http_hosts = http_host
    end

    for _, host in ipairs(http_hosts) do
        table.insert(endpoints, {
            full_prefix = host .. utils.normalize(api_prefix),
            http_host = host,
            api_prefix = api_prefix,
            version     = host .. '/version',
            stats_leader = host .. '/v2/stats/leader',
            stats_self   = host .. '/v2/stats/self',
            stats_store  = host .. '/v2/stats/store',
            keys        = host .. '/v2/keys',
        })
    end

    return setmetatable({
        init_count = 0,
        timeout = timeout,
        ttl = ttl,
        key_prefix = key_prefix,
        is_cluster = #endpoints > 1,
        user = user,
        password = password,
        endpoints = endpoints,
        serializer = serializer,
        ssl_verify = ssl_verify,
    },
    mt)
end

    local content_type = {
        ["Content-Type"] = "application/x-www-form-urlencoded",
    }

local function choose_endpoint(self)
    local endpoints = self.endpoints
    local endpoints_len = #endpoints
    if endpoints_len == 1 then
        return endpoints[1]
    end

    self.init_count = (self.init_count or 0) + 1
    local pos = self.init_count % endpoints_len + 1
    if self.init_count >= INIT_COUNT_RESIZE then
        self.init_count = 0
    end

    return endpoints[pos]
end


-- todo: test cover
-- return key, value
-- example: 'Authorization', 'Basic dsfsfsddsfddsdsffd=='
local function create_basicauth(user, password)
    local userPwd = user .. ':' .. password
    local base64Str = encode_base64(userPwd)
    return 'Authorization', 'Basic ' .. base64Str
end


local function _request(self, method, uri, opts, timeout)
    local body
    if opts and opts.body and table_exist_keys(opts.body) then
        body = encode_args(opts.body)
    end

    if opts and opts.query and table_exist_keys(opts.query) then
        uri = uri .. '?' .. encode_args(opts.query)
    end

    local http_cli, err = http.new()
    if err then
        return nil, err
    end

    if timeout then
        http_cli:set_timeout(timeout * 1000)
    end

    local headers = {
        ['Content-Type'] = content_type['Content-Type'],
    }
    if self.user and self.password then
        local bauth_key, bauth_val = create_basicauth(self.user, self.password)
        headers[bauth_key] = bauth_val
    end

    local res
    res, err = http_cli:request_uri(uri, {
        method = method,
        body = body,
        headers = headers,
        ssl_verify = self.ssl_verify,
    })

    if err then
        return nil, err
    end

    if res.status >= 500 then
        return nil, "invalid response code: " .. res.status
    end

    if res.status == 401 then
        return nil, "insufficient credentials code: " .. res.status
    end

    if not typeof.string(res.body) then
        return res
    end

    res.body = decode_json(res.body)
    return res
end


local function set(self, key, val, attr)
    local err
    if val then
        val, err = self.serializer.serialize(val)

        if err then
            return nil, err
        end
    end

    local prev_exist
    if attr.prev_exist ~= nil then
        prev_exist = attr.prev_exist and 'true' or 'false'
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
            prevExist = prev_exist,
            prevIndex = attr.prev_index,
        }
    }

    -- verify key
    key = utils.normalize(key)
    if key == '/' then
        return nil, "key should not be a slash"
    end

    local res
    res, err = _request(self, attr.in_order and 'POST' or 'PUT',
                        choose_endpoint(self).full_prefix .. "/keys" .. key,
                        opts, self.timeout)

    if err then
        return nil, err
    end

    -- get
    if res.status < 300 and res.body.node and not res.body.node.dir then
        res.body.node.value, err = self.serializer.deserialize(res.body.node.value)
        if err then
            utils.log_error("failed to deserialize value of node: ", err)
            return res, err
        end
    end

    return res
end


local function decode_dir_value(self, body_node)
    if not body_node.dir then
        return false
    end

    if type(body_node.nodes) ~= "table" then
        return false
    end

    local err
    for _, node in ipairs(body_node.nodes) do
        local val = node.value
        if type(val) == "string" then
            node.value, err = self.serializer.deserialize(val)
            if err then
                utils.log_error("failed to deserialize: ", err)
            end
        end

        decode_dir_value(self, node)
    end

    return true
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
                waitIndex = attr.wait_index,
                recursive = attr_recursive,
                consistent = attr.consistent,   -- todo
            }
        }
    end

    local res, err = _request(self, "GET",
            choose_endpoint(self).full_prefix .. "/keys" .. utils.normalize(key),
            opts, attr and attr.timeout or self.timeout)
    if err then
        return res, err
    end

    -- readdir
    if attr and attr.dir then
        if res.status == 200 and res.body.node and
           not res.body.node.dir then
            res.body.node.dir = false
        end
    end

    if res.status == 200 and res.body.node then
        local ok = decode_dir_value(self, res.body.node)
        if not ok then
            local val = res.body.node.value
            if type(val) == "string" then
                res.body.node.value, err = self.serializer.deserialize(val)
                if err then
                    utils.log_error("failed to deserialize: ", err)
                end
            end
        end
    end

    return res
end


local function delete(self, key, attr)
    local val, err = attr.prev_value
    if val ~= nil and type(val) ~= "number" then
        val, err = self.serializer.serialize(val)
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
            prevIndex = attr.prev_index,
            recursive = attr_recursive,
            prevValue = val,
        },
    }

    -- todo: check arguments
    return _request(self, "DELETE",
                    choose_endpoint(self).full_prefix .. "/keys" .. utils.normalize(key),
                    opts, self.timeout)
end

do

function _M.get(self, key)
    if not typeof.string(key) then
        return nil, 'key must be string'
    end

    key = utils.get_real_key(self.key_prefix, key)

    return get(self, key)
end

    local attr = {}
function _M.wait(self, key, modified_index, timeout)
    clear_tab(attr)
    attr.wait = true
    attr.wait_index = modified_index
    attr.timeout = timeout

    key = utils.get_real_key(self.key_prefix, key)

    return get(self, key, attr)
end

function _M.readdir(self, key, recursive)
    clear_tab(attr)
    attr.dir = true
    attr.recursive = recursive

    key = utils.get_real_key(self.key_prefix, key)

    return get(self, key, attr)
end

-- wait with recursive
function _M.waitdir(self, key, modified_index, timeout)
    clear_tab(attr)
    attr.wait = true
    attr.dir = true
    attr.recursive = true
    attr.wait_index = modified_index
    attr.timeout = timeout

    key = utils.get_real_key(self.key_prefix, key)

    return get(self, key, attr)
end

-- /version
function _M.version(self)
    return _request(self, 'GET', choose_endpoint(self).version, nil,
                    self.timeout)
end

-- /stats
function _M.stats_leader(self)
    return _request(self, 'GET', choose_endpoint(self).stats_leader, nil,
                    self.timeout)
end

function _M.stats_self(self)
    return _request(self, 'GET', choose_endpoint(self).stats_self, nil,
                    self.timeout)
end

function _M.stats_store(self)
    return _request(self, 'GET', choose_endpoint(self).stats_store, nil,
                    self.timeout)
end

end -- do


do
    local attr = {}
function _M.set(self, key, val, ttl)
    clear_tab(attr)
    attr.ttl = ttl

    key = utils.get_real_key(self.key_prefix, key)

    return set(self, key, val, attr)
end

-- set key-val and ttl if key does not exists (atomic create)
function _M.setnx(self, key, val, ttl)
    clear_tab(attr)
    attr.ttl = ttl
    attr.prev_exist = false

    key = utils.get_real_key(self.key_prefix, key)

    return set(self, key, val, attr)
end

-- set key-val and ttl if key is exists (update)
function _M.setx(self, key, val, ttl, modified_index)
    clear_tab(attr)
    attr.ttl = ttl
    attr.prev_exist = true
    attr.prev_index = modified_index

    key = utils.get_real_key(self.key_prefix, key)

    return set(self, key, val, attr)
end

-- dir
function _M.mkdir(self, key, ttl)
    clear_tab(attr)
    attr.ttl = ttl
    attr.dir = true

    key = utils.get_real_key(self.key_prefix, key)

    return set(self, key, nil, attr)
end

-- mkdir if not exists
function _M.mkdirnx(self, key, ttl)
    clear_tab(attr)
    attr.ttl = ttl
    attr.dir = true
    attr.prev_exist = false

    key = utils.get_real_key(self.key_prefix, key)

    return set(self, key, nil, attr)
end

-- in-order keys
function _M.push(self, key, val, ttl)
    clear_tab(attr)
    attr.ttl = ttl
    attr.in_order = true

    key = utils.get_real_key(self.key_prefix, key)

    return set(self, key, val, attr)
end

end -- do


do
    local attr = {}
function _M.delete(self, key, prev_val, modified_index)
    clear_tab(attr)
    attr.prev_value = prev_val
    attr.prev_index = modified_index

    key = utils.get_real_key(self.key_prefix, key)

    return delete(self, key, attr)
end

function _M.rmdir(self, key, recursive)
    clear_tab(attr)
    attr.dir = true
    attr.recursive = recursive

    key = utils.get_real_key(self.key_prefix, key)

    return delete(self, key, attr)
end

end -- do


return _M
