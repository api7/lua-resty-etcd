Name
====

[resty-etcd](https://github.com/iresty/lua-resty-etcd) Nonblocking Lua etcd driver library for OpenResty, this module supports etcd API v2 and v3.

[![Build Status](https://travis-ci.org/iresty/lua-resty-etcd.svg?branch=master)](https://travis-ci.org/iresty/lua-resty-etcd)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/iresty/lua-resty-etcd/blob/master/LICENSE)

Table of Contents
=================
* [Install](#install)
* [API v2](api_v2.md)
* [API v3](api_v3.md)

## Install

> Dependencies

- lua-resty-http: https://github.com/ledgetech/lua-resty-http
- lua-typeof: https://github.com/iresty/lua-typeof

> install by luarocks

```shell
luarocks install lua-resty-etcd
```

> install by source

```shell
$ luarocks install lua-resty-http lua-typeof
$ git clone https://github.com/iresty/lua-resty-etcd.git
$ cd lua-resty-etcd
$ sudo make install
```

[Back to TOC](#table-of-contents)
