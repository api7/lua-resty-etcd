Name
====

[resty-etcd](https://github.com/iresty/lua-resty-etcd) Nonblocking Lua etcd driver library for OpenResty, this module supports etcd API v2.

[![Build Status](https://travis-ci.org/iresty/lua-resty-etcd.svg?branch=master)](https://travis-ci.org/iresty/lua-resty-etcd)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/iresty/lua-resty-etcd/blob/master/LICENSE)

Table of Contents
=================
* [Install](#install)
* [Methods](#methods)
    * [new](#new)
    * [get](#get)
    * [set](#set)
    * [setnx](#setnx)
    * [setx](#setx)
    * [delete](#delete)
    * [wait](#wait)
    * [readdir](#readdir)
    * [mkdir](#mkdir)
    * [rmdir](#rmdir)
    * [waitdir](#waitdir)
    * [push](#push)
    * [version](#version)
    * [stats_leader](#stats_leader)
    * [stats_self](#stats_self)
    * [stats_store](#stats_store)


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

Method
======

### new

`syntax: cli, err = etcd.new([option:table])`

- `option:table`
  - `host`: string - default `http://127.0.0.1:2379`
  - `ttl`: int - default `-1`
    default ttl for key operation. set -1 to disable ttl.
  - `prefix`: string
    append this prefix path string to key operation url `'/v2/keys'`.
  - `timeout`: int
    request timeout seconds.

The client methods returns either a `HTTP Response Entity` or an `error string`.

`HTTP Response Entity` contains the following fields except `408` timeout status;

- `status`: number - HTTP status code.
- `header`: table - response header if `status` is not `408` timeout status.
- `body`: string or table - response body if `status` is not `408` timeout status.

**Note:** a client method will decode a response body as a JSON string if a `Content-Type` response header value is a `application/json`.

```lua
local cli, err = require('resty.etcd').new()
```

Please refer the **etcd API documentaion** at - https://github.com/coreos/etcd for more details of a response entity.

[Back to TOC](#table-of-contents)

### get

`syntax: res, err = cli:get(key:string)`

Gets the value for key.

```lua
local res, err = cli:get('/path/to/key')
```

[Back to TOC](#table-of-contents)

### set

`syntax: res, err = cli:set(key:string, val:JSON value [, ttl:int])`

Set a key-value pair.

```lua
local res, err = cli:set('/path/to/key', 'val', 10)
```

[Back to TOC](#table-of-contents)

### setnx

`syntax: res, err = cli:setnx(key:string, val:JSON value [, ttl:int])`

Set a key-value pair if that key does not exist.

```lua
local res, err = cli:setnx('/path/to/key', 'val', 10)
```

[Back to TOC](#table-of-contents)

### setx

`syntax: res, err = cli:setx(key:string, val:JSON value [, ttl:int [, modified_index:uint] ])`

- `modified_index`: uint - this argument to use to the `prev_index` query of atomic operation.

Set a key-value pair when that key is exists.

```lua
local res, err = cli:setx('/path/to/key', 'val', 10)
```

```lua
local res, err = cli:get('/path/to/key')

-- this operation will be failed if the `modified_index` of specified key
-- has already been updated by another client.
res, err = cli:setx('/path/to/key', 'val', 10, res.body.node.modifiedIndex)
```

[Back to TOC](#table-of-contents)

### delete

`syntax: res, err = cli:delete(key:string [, val:JSON value [, modified_index:uint] ])`

- `val`: JSON value - this argument to use to the `prevValue` query of atomic operation.
- `modified_index`: uint - this argument to use to the `prev_index` query of atomic operation.

Deletes a key-value pair.

```lua
local res, err = cli:delete('/path/to/key')
```

```lua
local res, err = cli:get('/path/to/key')

-- delete key-value pair if both of `value` and `modified_index` has matched
-- to the passed arguments
res, err = cli:delete('/path/to/key', res.body.node.value,
                      res.body.node.modifiedIndex)

-- delete key-value pair if `value` has matched to the passed value
res, err = cli:delete('/path/to/key', res.body.node.value)

-- delete key-value pair if `modified_index` has matched to the passed
-- modifiedIndex
res, err = cli:delete('/path/to/key', nil, res.body.node.modifiedIndex)

```

[Back to TOC](#table-of-contents)

### wait

`syntax: res, err = cli:wait(key:string [, modified_index:uint [, timeout:uint] ]) `

- `modified_index`: uint - this argument to use to the `prev_index` query of atomic operation.
- `timeout`: uint - request timeout seconds. set 0 to disable timeout.

Wait the update of key.

```lua
local res, err = cli:wait('/path/to/key')
```

```lua
local res, err = cli:get('/path/to/key')

-- Wait forever the update of key until that modifiedIndex of key has changed
-- to modifiedIndex + 1
res, err = cli:wait('/path/to/key', res.body.node.modifiedIndex + 1, 0)

-- Wait for 10 seconds the update of key until that modifiedIndex of key has
-- changed to modifiedIndex + 2
res, err = cli:wait('/path/to/key', res.body.node.modifiedIndex + 2, 10)
```

[Back to TOC](#table-of-contents)

### readdir

`syntax: res, err = cli:readdir(key:string [, recursive:boolean])`

- `recursive`: boolean - get all the contents under a directory.

Read the directory.

```lua
local res, err = cli:readdir('/path/to/dir')
```

[Back to TOC](#table-of-contents)

### mkdir

`syntax: res, err = cli:mkdir(key:string [, ttl:int])`

Creates a directory.

```lua
local res, err = cli:mkdir('/path/to/dir', 10)
```

[Back to TOC](#table-of-contents)

### mkdirnx

`syntax: res, err = cli:mkdirnx(key:string [, ttl:int])`

Creates a directory if that directory does not exist.

```lua
local res, err = cli:mkdirnx('/path/to/dir', 10)
```

[Back to TOC](#table-of-contents)

### rmdir

`syntax: res, err = cli:rmdir(key:string [, recursive:boolean])`

- `recursive`: boolean - remove all the contents under a directory.

Remove the directory

```lua
local res, err = cli:rmdir('/path/to/dir')
```

[Back to TOC](#table-of-contents)

### waitdir

`syntax: res, err = cli:waitdir(key:string [, modified_index:uint [, timeout:uint] ])`


- `modified_index`: uint - this argument to use to the `prev_index` query of atomic operation.
- `timeout`: uint - request timeout seconds. set 0 to disable timeout.

```lua
local res, err = cli:waitdir('/path/to/dir')
```

[Back to TOC](#table-of-contents)

### push

`syntax: res, err = cli:push(key:string, val:JSON value [, ttl:int])`

Pushs a value into the specified directory.

```lua
local res, err = cli:mkdir('/path/to/dir')
res, err = cli:push('/path/to/dir', 'val', 10)
```

[Back to TOC](#table-of-contents)

### version

`syntax: res, err = cli:version()`

Gets the etcd version info.

[Back to TOC](#table-of-contents)

### stats_leader

`syntax: res, err = cli:stats_leader()`

Gets the leader statistics info.

[Back to TOC](#table-of-contents)

### stats_self

`syntax: res, err = cli:stats_self()`

Gets the self statistics info.

[Back to TOC](#table-of-contents)

### stats_store

`syntax: res, err = cli:stats_store()`

Gets the store statistics info.

[Back to TOC](#table-of-contents)
