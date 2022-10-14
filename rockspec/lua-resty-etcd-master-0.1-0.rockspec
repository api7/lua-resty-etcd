package = "lua-resty-etcd-master"
version = "0.1-0"
source = {
   url = "git://github.com/iresty/lua-resty-etcd",
   branch = "master",
}

description = {
   summary = "Nonblocking Lua etcd driver library for OpenResty",
   homepage = "https://github.com/iresty/lua-resty-etcd",
   license = "Apache License 2.0",
   maintainer = "Yuansheng Wang <membphis@gmail.com>"
}

dependencies = {
   "api7-lua-resty-http = 0.1.0",
   "lua-protobuf = 0.3.4",
   "luafilesystem = 1.7.0-2",
   "penlight = 1.9.2-1",
   "lua-typeof = 0.1"
}

build = {
   type = "builtin",
   modules = {
    ["resty.etcd"] = "lib/resty/etcd.lua",
    ["resty.etcd.v3"] = "lib/resty/etcd/v3.lua",
    ["resty.etcd.utils"] = "lib/resty/etcd/utils.lua",
    ["resty.etcd.serializers.json"] = "lib/resty/etcd/serializers/json.lua",
    ["resty.etcd.serializers.raw"] = "lib/resty/etcd/serializers/raw.lua",
    ["resty.etcd.health_check"] = "lib/resty/etcd/health_check.lua",
   }
}
