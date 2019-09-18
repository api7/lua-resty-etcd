-- https://github.com/ledgetech/lua-resty-http
local typeof        = require("typeof")
local cjson         = require("cjson.safe")
local setmetatable  = setmetatable
local clear_tab     = require "table.clear"
local ipairs        = ipairs
local type          = type
local base64        = require("ngx.base64")
local utils         = require("resty.etcd.utils")
local tab_nkeys     = require "table.nkeys"


local _M = {
    decode_json = cjson.decode,
    encode_json = cjson.encode,
    encode_base64 = ngx.encode_base64,
    decode_base64 = ngx.decode_base64,
}
local mt = { __index = _M }


function _M.new(opts)
    if opts == nil then
        opts = {}

    elseif not typeof.table(opts) then
        return nil, 'opts must be table'
    end

    local timeout    = opts.timeout or 5000    -- 5 sec
    local http_host  = opts.host or "http://127.0.0.1:2379"
    local ttl        = opts.ttl or -1
    local api_prefix = opts.api_prefix or "/v3"
    local key_prefix = opts.key_prefix or "/apisix"

    if not typeof.uint(timeout) then
        return nil, 'opts.timeout must be unsigned integer'
    end

    if not typeof.string(http_host) then
        return nil, 'opts.host must be string'
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

    return setmetatable({
            timeout   = timeout,
            ttl       = ttl,
            endpoints = {
                full_prefix = http_host .. utils.normalize(api_prefix),
                http_host   = http_host,
                key_prefix  = key_prefix
            }
        },
        mt)
end

local function set(self, key, val, attr)
    local err
    val, err = self.encode_json(val)
    if not val then
        return nil, err
    end

    -- verify key
    key = utils.normalize(key)
    if key == '/' then
        return nil, "key should not be a slash"
    end

    key = self.encode_base64(key)
    val = self.encode_base64(val)

    attr = attr and attr or {}

    local lease
    if attr.lease then      
        lease = attr.lease and attr.lease or 0
    end

    local prev_kv
    if attr.prev_kv then
        prev_kv = attr.prev_kv and 'true' or 'false'
    end
    
    local ignore_value
    if attr.ignore_value then
        ignore_value = attr.ignore_value and 'true' or 'false'
    end

    local ignore_lease
    if attr.ignore_lease then
        ignore_lease = attr.ignore_lease and 'true' or 'false'
    end

    local opts = {
        body = {
            value        = val,
            key          = key,
            lease        = lease,
            prev_kv      = prev_kv,
            ignore_value = ignore_value,
            ignore_lease = ignore_lease,
        }
    }

    local res
    res, err = utils.request_uri(self, 'POST',
                        self.endpoints.full_prefix .. "/kv/put",
                        opts, self.timeout)
    if err then
        return nil, err
    end

    -- get
    if res.status < 300  then
        utils.log_error("v3 set body: ", self.encode_json(res.body))
    end

    return res
end

local function get(self, key, attr)
    -- verify key
    key = utils.normalize(key)
    if not key or key == '/' then
        return nil, "key invalid"
    end

    attr = attr and attr or {}

    local range_end
    if attr.range_end then
        range_end = self.encode_base64(range_end)
    end

    attr = attr and attr or {}

    local limit
    if attr.limit then
        limit = attr.limit and attr.limit or 0
    end

    local revision
    if attr.revision then
        revision = attr.revision and attr.revision or 0
    end

    local sort_order
    if attr.sort_order then
        sort_order = attr.sort_order and attr.sort_order or 0
    end

    local sort_target
    if attr.sort_target then
        sort_target = attr.sort_target and attr.sort_target or 0
    end

    local serializable
    if attr.serializable then
        serializable = attr.serializable and 'true' or 'false'
    end

    local keys_only
    if attr.keys_only then
        keys_only = attr.keys_only and 'true' or 'false'
    end

    local count_only
    if attr.count_only then
        count_only = attr.count_only and 'true' or 'false'
    end    

    local min_mod_revision
    if attr.min_mod_revision then
        min_mod_revision = attr.min_mod_revision and attr.min_mod_revision or 0
    end

    local max_mod_revision
    if attr.max_mod_revision then
        max_mod_revision = attr.max_mod_revision and attr.max_mod_revision or 0
    end

    local min_create_revision
    if attr.min_create_revision then
        min_create_revision = attr.min_create_revision and attr.min_create_revision or 0
    end

    local max_create_revision
    if attr.max_create_revision then
        max_create_revision = attr.max_create_revision and attr.max_create_revision or 0
    end


    key = self.encode_base64(key)

    local opts = {
        body = {
            key                 = key,
            range_end           = range_end,
            limit               = limit,
            revision            = revision,
            sort_order          = sort_order,
            sort_target         = sort_target,
            serializable        = serializable,
            keys_only           = keys_only,
            count_only          = count_only,
            min_mod_revision    = min_mod_revision,
            max_mod_revision    = max_mod_revision,
            min_create_revision = min_create_revision,
            max_create_revision = max_create_revision
        }
    }

    local res, err = utils.request_uri(self, "POST",
                              self.endpoints.full_prefix .. "/kv/range",
                              opts, attr and attr.timeout or self.timeout)

    if res.status==200 then
        if res.body.kvs and tab_nkeys(res.body.kvs)>0 then
            for i = 1, #res.body.kvs do  
                res.body.kvs[i].value = self.decode_base64(res.body.kvs[i].value)
                res.body.kvs[i].value = self.decode_json(res.body.kvs[i].value)
            end              
        end        
    end


    return res, err
end

local function delete(self, key, attr)
    attr = attr and attr or {}

    local range_end
    if attr.range_end then
        range_end = self.encode_base64(range_end)
    end

    local prev_kv
    if attr.prev_kv then
        prev_kv = attr.prev_kv and 'true' or 'false'
    end

    key = self.encode_base64(key)

    local opts = {
        body = {
            key       = key,
            range_end = range_end,
            prev_kv   = prev_kv,
        },
    }

    return utils.request_uri(self, "POST",
                    self.endpoints.full_prefix .. "/kv/deleterange",
                    opts, self.timeout)
end

local function watch(self, key, attr)
    -- verify key
    key = utils.normalize(key)
    if key == '/' then
        return nil, "key should not be a slash"
    end

    key = self.encode_base64(key)

    attr = attr and attr or {}

    local range_end
    if attr.range_end then      
        range_end = self.encode_base64(range_end)
    end

    local prev_kv
    if attr.prev_kv then
        prev_kv = attr.prev_kv and 'true' or 'false'
    end
    
    local start_revision
    if attr.start_revision then
        start_revision = attr.start_revision and attr.start_revision or 0
    end

    local watch_id
    if attr.watch_id then
        watch_id = attr.watch_id and attr.watch_id or 0
    end

    local progress_notify
    if attr.progress_notify then
        progress_notify = attr.progress_notify and 'true' or 'false'
    end

    local fragment
    if attr.fragment then
        fragment = attr.fragment and 'true' or 'false'
    end

    local filters
    if attr.filters then
        filters = attr.filters and attr.filters or 0
    end

    local opts = {
        body = {
            create_request = {
                key             = key,
                range_end       = range_end,
                prev_kv         = prev_kv,
                start_revision  = start_revision,
                watch_id        = watch_id,
                progress_notify = progress_notify,
                fragment        = fragment,
                filters         = filters,
            }
        }
    }

    local res, err
    res, err = utils.request_uri(self, 'POST',
                        self.endpoints.full_prefix .. "/kv/watch",
                        opts, self.timeout)
    return res, err
end



do

function _M.get(self, key)
    if not typeof.string(key) then
        return nil, 'key must be string'
    end

    return get(self, key)
end

    local attr = {}
function _M.watch(self, key, timeout)
    clear_tab(attr)
    attr.timeout = timeout

    return watch(self, key, attr)
end

function _M.readdir(self, key, recursive)
    clear_tab(attr)
    attr.dir = true
    attr.recursive = recursive

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

    return get(self, key, attr)
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
    attr.prev_exist = false

    return set(self, key, val, attr)
end

-- set key-val and ttl if key is exists (update)
function _M.setx(self, key, val, ttl, modified_index)
    clear_tab(attr)
    attr.ttl = ttl
    attr.prev_exist = true
    attr.prev_index = modified_index

    return set(self, key, val, attr)
end


end -- do


do
    local attr = {}
function _M.delete(self, key, prev_val, modified_index)
    clear_tab(attr)
    attr.prev_value = prev_val
    attr.prev_index = modified_index

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
