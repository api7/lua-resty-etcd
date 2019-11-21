-- https://github.com/ledgetech/lua-resty-http
local typeof        = require("typeof")
local cjson         = require("cjson.safe")
local setmetatable  = setmetatable
local clear_tab     = require("table.clear")
local utils         = require("resty.etcd.utils")
local tab_nkeys     = require("table.nkeys")
local encode_args   = ngx.encode_args
local now           = ngx.now
local sub_str       = string.sub
local str_byte      = string.byte
local str_char      = string.char
local ipairs        = ipairs
local re_match      = ngx.re.match
local type          = type
local tab_insert    = table.insert
local tab_clone     = require("table.clone")
local decode_json   = cjson.decode
local encode_json   = cjson.encode
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local INIT_COUNT_RESIZE = 2e8

local _M = {}

local mt = { __index = _M }

-- define local refresh function variable
local refresh_jwt_token

local function _request_uri(self, method, uri, opts, timeout, ignore_auth)

    local body
    if opts and opts.body and tab_nkeys(opts.body) > 0 then
        body = encode_json(opts.body) --encode_args(opts.body)
    end

    if opts and opts.query and tab_nkeys(opts.query) > 0 then
        uri = uri .. '?' .. encode_args(opts.query)
    end

    local headers = {}
    local keepalive = true
    if self.is_auth then
        if not ignore_auth then
            -- authentication reqeust not need auth request
            local _, err = refresh_jwt_token(self)
            if err then
                return nil, err
            end
        else
            keepalive = false   -- jwt_token not keepalive
        end
        headers.Authorization = self.jwt_token
    end

    local http_cli, err = utils.http.new()
    if err then
        return nil, err
    end

    if timeout then
        http_cli:set_timeout(timeout * 1000)
    end

    utils.log_info('uri:', uri, ' body:', body)

    local res
    res, err = http_cli:request_uri(uri, {
        method = method,
        body = body,
        headers = headers,
        keepalive = keepalive,
    })

    if err then
        return nil, err
    end

    utils.log_info('res body:', res.body, 'status:', res.status)

    if res.status >= 500 then
        return nil, "invalid response code: " .. res.status
    end

    if not typeof.string(res.body) then
        return res
    end

    res.body = decode_json(res.body)
    return res
end


local function encode_json_base64(data)
    local err
    data, err = encode_json(data)
    if not data then
        return nil, err
    end
    return encode_base64(data)
end


function _M.new(opts)
    local timeout    = opts.timeout
    local ttl        = opts.ttl
    local api_prefix = opts.api_prefix
    local key_prefix = opts.key_prefix or ""
    local http_host  = opts.http_host
    local user = opts.user
    local password = opts.password

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
        local m, err = re_match(host, [[\/\/([\d.\w]+):(\d+)]], "jo")
        if not m then
            return nil, "invalid http host: " .. err
        end

        tab_insert(endpoints, {
            full_prefix = host .. utils.normalize(api_prefix),
            http_host   = host,
            host        = m[1] or "127.0.0.1",
            port        = m[2] or "2379",
            api_prefix  = api_prefix,
        })
    end

    return setmetatable({
            last_auth_time = now(), -- save last Authentication time
            jwt_token   = nil,       -- last Authentication token
            is_auth     = not not (user and password),
            user       = user,
            password   = password,
            timeout    = timeout,
            ttl        = ttl,
            is_cluster = #endpoints > 1,
            endpoints  = endpoints,
            key_prefix  = key_prefix,
        },
        mt)
end


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

-- return refresh_is_ok, error
function refresh_jwt_token(self)
    -- token exist and not expire
    -- default is 5min, we use 3min
    -- https://github.com/etcd-io/etcd/issues/8287
    if self.jwt_token and now() - self.last_auth_time < 60 * 3 then
        return true, nil
    end

    local opts = {
        body = {
            name         = self.user,
            password     = self.password,
        }
    }
    local res, err = _request_uri(self, 'POST',
                        choose_endpoint(self).full_prefix .. "/auth/authenticate",
                        opts, 5, true)    -- default authenticate timeout 5 second
    if err then
        return nil, err
    end

    if not res or not res.body or not res.body.token then
        return nil, 'authenticate refresh token fail'
    end

    self.jwt_token = res.body.token
    self.last_auth_time = now()

    return true, nil
end

local function set(self, key, val, attr)
    -- verify key
    key = utils.normalize(key)
    if key == '/' then
        return nil, "key should not be a slash"
    end

    key = encode_base64(key)
    local err
    val, err = encode_json_base64(val)
    if not val then
        return nil, err
    end

    attr = attr or {}

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
    res, err = _request_uri(self, 'POST',
                        choose_endpoint(self).full_prefix .. "/kv/put",
                        opts, self.timeout)
    if err then
        return nil, err
    end

    -- get
    if res.status < 300  then
        -- TODO(optimize): delay json encode
        utils.log_info("v3 set body: ", encode_json(res.body))
    end

    return res
end

local function get(self, key, attr)
    -- verify key
    key = utils.normalize(key)
    if not key or key == '/' then
        return nil, "key invalid"
    end

    attr = attr or {}

    local range_end
    if attr.range_end then
        range_end = encode_base64(attr.range_end)
    end

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
        min_mod_revision = attr.min_mod_revision or 0
    end

    local max_mod_revision
    if attr.max_mod_revision then
        max_mod_revision = attr.max_mod_revision or 0
    end

    local min_create_revision
    if attr.min_create_revision then
        min_create_revision = attr.min_create_revision or 0
    end

    local max_create_revision
    if attr.max_create_revision then
        max_create_revision = attr.max_create_revision or 0
    end

    key = encode_base64(key)

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

    local res, err = _request_uri(self, "POST",
                              choose_endpoint(self).full_prefix .. "/kv/range",
                              opts, attr and attr.timeout or self.timeout)

    if res and res.status==200 then
        if res.body.kvs and tab_nkeys(res.body.kvs)>0 then
            for _, kv in ipairs(res.body.kvs) do
                kv.key = decode_base64(kv.key)
                kv.value = decode_base64(kv.value)
                kv.value = decode_json(kv.value)
            end
        end
    end

    return res, err
end

local function delete(self, key, attr)
    attr = attr and attr or {}

    local range_end
    if attr.range_end then
        range_end = encode_base64(attr.range_end)
    end

    local prev_kv
    if attr.prev_kv then
        prev_kv = attr.prev_kv and 'true' or 'false'
    end

    key = encode_base64(key)

    local opts = {
        body = {
            key       = key,
            range_end = range_end,
            prev_kv   = prev_kv,
        },
    }

    return _request_uri(self, "POST",
                    choose_endpoint(self).full_prefix .. "/kv/deleterange",
                    opts, self.timeout)
end

local function txn(self, opts_arg, compare, success, failure)
    if #compare < 1 then
        return nil, "compare couldn't be empty"
    end

    if (success==nil or #success < 1) and (failure==nil or #failure<1) then
        return nil, "success and failure couldn't be empty at the same time"
    end

    local timeout = opts_arg and opts_arg.timeout
    local opts = {
        body = {
            compare = compare,
            success = success,
            failure = failure,
        },
    }

    return _request_uri(self, "POST",
                        choose_endpoint(self).full_prefix .. "/kv/txn",
                        opts, timeout or self.timeout)
end


local function request_chunk(self, method, host, port, path, opts, timeout)
    local body, err, _
    if opts and opts.body and tab_nkeys(opts.body) > 0 then
        body, err = encode_json(opts.body)
        if not body then
            return nil, err
        end
    end

    local query
    if opts and opts.query and tab_nkeys(opts.query) > 0 then
        query = encode_args(opts.query)
    end

    local headers = {}
    if self.is_auth then
        -- authentication reqeust not need auth request
        _, err = refresh_jwt_token(self)
        if err then
            return nil, err
        end
        headers.Authorization = self.jwt_token
    end

    local http_cli
    http_cli, err = utils.http.new()
    if err then
        return nil, err
    end

    local ok, _
    if timeout then
        _, err = http_cli:set_timeout(timeout * 1000)
        if err then
            return nil, err
        end
    end

    ok, err = http_cli:connect(host, port)
    if not ok then
        return nil, err
    end

    local res
    res, err = http_cli:request({
        method  = method,
        path    = path,
        body    = body,
        query   = query,
        headers = headers,
    })
    utils.log_info("http request method: ", method, " path: ", path,
             " body: ", body, " query: ", query)

    if not res then
        return nil, err
    end

    if res.status >= 300 then
        return nil, "failed to watch data, response code: " .. res.status
    end

    return function()
        local body, err = res.body_reader()
        if not body then
            return nil, err
        end

        body, err = decode_json(body)
        if not body then
            return nil, "failed to decode json body: " .. (err or " unkwon")
        end

        if body.result.events then
            for _, event in ipairs(body.result.events) do
                if event.kv.value then   -- DELETE not have value
                    event.kv.value = decode_base64(event.kv.value)
                    event.kv.value = decode_json(event.kv.value)
                end
                event.kv.key = decode_base64(event.kv.key)
            end
        end

        return body
    end
end


local function get_range_end(key)
    local last = sub_str(key, -1)
    key = sub_str(key, 1, #key-1)
    local has_slash = false
    if last == '/' then
        last = sub_str(key, -1)
        key  = sub_str(key, 1, #key-1)
        has_slash = true
    end

    if key == '/' then
        return nil, "invalid key"
    end

    local ascii = str_byte(last) + 1
    local str   = str_char(ascii)

    return key .. str .. (has_slash and '/' or '')
end


local function watch(self, key, attr)
    -- verify key
    key = utils.normalize(key)
    if key == '/' then
        return nil, "key should not be a slash"
    end

    key = encode_base64(key)

    local range_end
    if attr.range_end then
        range_end = encode_base64(attr.range_end)
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

    local endpoint = choose_endpoint(self)
    local callback_fun, err = request_chunk(self, 'POST',
                                endpoint.host,
                                endpoint.port,
                                endpoint.api_prefix .. '/watch', opts,
                                attr.timeout or self.timeout)
    if not callback_fun then
        return nil, err
    end

    return callback_fun
end


do
    local attr = {}
function _M.get(self, key, opts)
    if not typeof.string(key) then
        return nil, 'key must be string'
    end

    key = utils.get_real_key(self.key_prefix, key)

    clear_tab(attr)
    attr.timeout = opts and opts.timeout
    attr.revision = opts and opts.revision

    return get(self, key)
end

function _M.watch(self, key, opts)
    clear_tab(attr)

    key = utils.get_real_key(self.key_prefix, key)

    attr.start_revision  = opts and opts.start_revision
    attr.timeout = opts and opts.timeout
    attr.progress_notify = opts and opts.progress_notify
    attr.filters  = opts and opts.filters
    attr.prev_kv  = opts and opts.prev_kv
    attr.watch_id = opts and opts.watch_id
    attr.fragment = opts and opts.fragment

    return watch(self, key, attr)
end

function _M.readdir(self, key, opts)

    clear_tab(attr)
    
    key = utils.get_real_key(self.key_prefix, key)

    attr.range_end = get_range_end(key)
    attr.revision = opts and opts.revision
    attr.timeout  = opts and opts.timeout
    attr.limit        = opts and opts.limit
    attr.sort_order   = opts and opts.sort_order
    attr.sort_target  = opts and opts.sort_target
    attr.keys_only    = opts and opts.keys_only
    attr.count_only   = opts and opts.count_only

    return get(self, key, attr)
end

function _M.watchdir(self, key, opts)
    clear_tab(attr)
    
    key = utils.get_real_key(self.key_prefix, key)
    
    attr.range_end = get_range_end(key)
    attr.start_revision  = opts and opts.start_revision
    attr.timeout = opts and opts.timeout
    attr.progress_notify = opts and opts.progress_notify
    attr.filters  = opts and opts.filters
    attr.prev_kv  = opts and opts.prev_kv
    attr.watch_id = opts and opts.watch_id
    attr.fragment = opts and opts.fragment

    return watch(self, key, attr)
end

end -- do


do
    local attr = {}
function _M.set(self, key, val, opts)

    clear_tab(attr)
    
    key = utils.get_real_key(self.key_prefix, key)

    attr.timeout = opts and opts.timeout
    attr.lease   = opts and opts.lease
    attr.prev_kv = opts and opts.prev_kv
    attr.ignore_value = opts and opts.ignore_value
    attr.ignore_lease = opts and opts.ignore_lease

    return set(self, key, val, attr)
end

    -- set key-val if key does not exists (atomic create)
    local compare = {}
    local success = {}
    local failure = {}
function _M.setnx(self, key, val, opts)
    clear_tab(compare)
    
    key = utils.get_real_key(self.key_prefix, key)

    compare[1] = {}
    compare[1].target = "CREATE"
    compare[1].key    = encode_base64(key)
    compare[1].createRevision = 0

    clear_tab(success)
    success[1] = {}
    success[1].requestPut = {}
    success[1].requestPut.key = encode_base64(key)

    local err
    val, err = encode_json_base64(val)
    if not val then
        return nil, "failed to encode val: " .. err
    end
    success[1].requestPut.value = val

    return txn(self, opts, compare, success, nil)
end

-- set key-val and ttl if key is exists (update)
function _M.setx(self, key, val, opts)
    clear_tab(compare)
    
    key = utils.get_real_key(self.key_prefix, key)

    compare[1] = {}
    compare[1].target = "CREATE"
    compare[1].key    = encode_base64(key)
    compare[1].createRevision = 0

    clear_tab(failure)
    failure[1] = {}
    failure[1].requestPut = {}
    failure[1].requestPut.key = encode_base64(key)

    local err
    val, err = encode_json_base64(val)
    if not val then
        return nil, "failed to encode val: " .. err
    end
    failure[1].requestPut.value = val

    return txn(self, opts, compare, nil, failure)
end

end -- do


function _M.txn(self, compare, success, failure, opts)
    local err

    if compare then
        local new_rules = tab_clone(compare)
        for i, rule in ipairs(compare) do
            rule = tab_clone(rule)

            rule.key = encode_base64(utils.get_real_key(self.key_prefix, rule.key))

            if rule.value then
                rule.value, err = encode_json_base64(rule.value)
                if not rule.value then
                    return nil, "failed to encode value: " .. err
                end
            end

            new_rules[i] = rule
        end
        compare = new_rules
    end

    if success then
        local new_rules = tab_clone(success)
        for i, rule in ipairs(success) do
            rule = tab_clone(rule)
            if rule.requestPut then
                local requestPut = tab_clone(rule.requestPut)
                requestPut.key = encode_base64(utils.get_real_key(self.key_prefix, requestPut.key))

                requestPut.value, err = encode_json_base64(requestPut.value)
                if not requestPut.value then
                    return nil, "failed to encode value: " .. err
                end

                rule.requestPut = requestPut
            end
            new_rules[i] = rule
        end
        success = new_rules
    end

    return txn(self, opts, compare, success, failure)
end


-- /version
function _M.version(self)
    return _request_uri(self, "GET",
                        choose_endpoint(self).http_host .. "/version",
                        nil, self.timeout)
end

-- /stats
function _M.stats_leader(self)
    return _request_uri(self, "GET",
                        choose_endpoint(self).http_host .. "/v2/stats/leader",
                        nil, self.timeout)
end

function _M.stats_self(self)
    return _request_uri(self, "GET",
                        choose_endpoint(self).http_host .. "/v2/stats/self",
                        nil, self.timeout)
end

function _M.stats_store(self)
    return _request_uri(self, "GET",
                        choose_endpoint(self).http_host .. "/v2/stats/store",
                        nil, self.timeout)
end


do
    local attr = {}
function _M.delete(self, key, opts)
    clear_tab(attr)
    
    key = utils.get_real_key(self.key_prefix, key)

    attr.timeout = opts and opts.timeout
    attr.prev_kv = opts and opts.prev_kv

    return delete(self, key, attr)
end

function _M.rmdir(self, key, opts)
    clear_tab(attr)
    
    key = utils.get_real_key(self.key_prefix, key)

    attr.range_end = get_range_end(key)
    attr.timeout   = opts and opts.timeout
    attr.prev_kv   = opts and opts.prev_kv

    return delete(self, key, attr)
end

end -- do


return _M
