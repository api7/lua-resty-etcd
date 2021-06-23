package = "lua-resty-etcd"
version = "1.5.2-0"
source = {
   url = "git://github.com/api7/lua-resty-etcd",
   tag = "v1.5.2"
}

description = {
   summary = "Nonblocking Lua etcd driver library for OpenResty",
   homepage = "https://github.com/api7/lua-resty-etcd",
   license = "Apache License 2.0"
}

dependencies = {
   "api7-lua-resty-http = 0.1.0",
   "lua-typeof = 0.1"
}

build = {
   type = "builtin",
   modules = {
    ["resty.etcd"] = "lib/resty/etcd.lua",
    ["resty.etcd.v2"] = "lib/resty/etcd/v2.lua",
    ["resty.etcd.v3"] = "lib/resty/etcd/v3.lua",
    ["resty.etcd.utils"] = "lib/resty/etcd/utils.lua",
    ["resty.etcd.serializers.json"] = "lib/resty/etcd/serializers/json.lua",
    ["resty.etcd.serializers.raw"] = "lib/resty/etcd/serializers/raw.lua",
    ["resty.etcd.health_check"] = "lib/resty/etcd/health_check.lua",
   }
}
