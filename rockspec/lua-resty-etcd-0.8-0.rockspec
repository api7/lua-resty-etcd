package = "lua-resty-etcd"
version = "0.8-0"
source = {
   url = "git://github.com/iresty/lua-resty-etcd",
   tag = "v0.8"
}
description = {
   summary = "Nonblocking Lua etcd driver library for OpenResty",
   homepage = "https://github.com/iresty/lua-resty-etcd",
   license = "Apache License 2.0",
   maintainer = "Yuansheng Wang <membphis@gmail.com>"
}
dependencies = {
   "lua-resty-http = 0.15",
   "lua-typeof = 0.1"
}
build = {
   type = "builtin",
   modules = {
      ["resty.etcd"] = "lib/resty/etcd.lua",
      ["resty.etcd.v2"] = "lib/resty/etcd/v2.lua",
      ["resty.etcd.v3"] = "lib/resty/etcd/v3.lua",
      ["resty.etcd.utils"] = "lib/resty/etcd/utils.lua",
   }
}