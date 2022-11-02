Name
====

[lua-resty-etcd](https://github.com/iresty/lua-resty-etcd) Nonblocking Lua etcd driver library for OpenResty, this module supports etcd API v3.

[![Build Status](https://github.com/api7/lua-resty-etcd/actions/workflows/ci.yml/badge.svg)](https://github.com/api7/lua-resty-etcd/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/iresty/lua-resty-etcd/blob/master/LICENSE)

Table of Contents
=================
* [Install](#install)
* [API v3](api_v3.md)
  * **NOTE**: Requires ETCD version >= v3.4.0

## Install

> Dependencies

- api7-lua-resty-http: https://github.com/api7/lua-resty-http
- lua-typeof: https://github.com/iresty/lua-typeof

> install by luarocks

```shell
luarocks install lua-resty-etcd
```

> install by source

```shell
$ git clone https://github.com/iresty/lua-resty-etcd.git
$ cd lua-resty-etcd
$ make dev
$ sudo make install
```

