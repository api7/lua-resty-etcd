API V2
======

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

Method
======

### new

`syntax: cli, err = etcd.new([option:table])`

- `option:table`
  - `protocol`: string - default `v2`.
  - `http_host`: string - default `http://127.0.0.1:2379`
  - `ttl`: int - default `-1`
    default ttl for key operation. set -1 to disable ttl.
  - `key_prefix`: string
    append this prefix path string to key operation url `'/v2/keys'`.
  - `timeout`: int
    request timeout seconds.
  - `serializer`: string - serializer type, default `json`, also support `raw` to keep origin string value. 
  - `ssl_verify`: boolean - whether to verify the etcd certificate when originating TLS connection with etcd (if you want to communicate to etcd with TLS connection, use `https` scheme in your `http_host`), default is `true`.

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

[Back to TOP](#api-v2)

### get

`syntax: res, err = cli:get(key:string)`

Gets the value for key.

```lua
local res, err = cli:get('/path/to/key')
```

[Back to TOP](#api-v2)

### set

`syntax: res, err = cli:set(key:string, val:JSON value [, ttl:int])`

Set a key-value pair.

```lua
local res, err = cli:set('/path/to/key', 'val', 10)
```

[Back to TOP](#api-v2)

### setnx

`syntax: res, err = cli:setnx(key:string, val:JSON value [, ttl:int])`

Set a key-value pair if that key does not exist.

```lua
local res, err = cli:setnx('/path/to/key', 'val', 10)
```

[Back to TOP](#api-v2)

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

[Back to TOP](#api-v2)

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

[Back to TOP](#api-v2)

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

[Back to TOP](#api-v2)

### readdir

`syntax: res, err = cli:readdir(dir:string [, recursive:boolean])`

- `recursive`: boolean - get all the contents under a directory.

Read the directory.

```lua
local res, err = cli:readdir('/path/to/dir')
```

[Back to TOP](#api-v2)

### mkdir

`syntax: res, err = cli:mkdir(dir:string [, ttl:int])`

Creates a directory.

```lua
local res, err = cli:mkdir('/path/to/dir', 10)
```

[Back to TOP](#api-v2)

### mkdirnx

`syntax: res, err = cli:mkdirnx(dir:string [, ttl:int])`

Creates a directory if that directory does not exist.

```lua
local res, err = cli:mkdirnx('/path/to/dir', 10)
```

[Back to TOP](#api-v2)

### rmdir

`syntax: res, err = cli:rmdir(dir:string [, recursive:boolean])`

- `recursive`: boolean - remove all the contents under a directory.

Remove the directory

```lua
local res, err = cli:rmdir('/path/to/dir')
```

[Back to TOP](#api-v2)

### waitdir

`syntax: res, err = cli:waitdir(dir:string [, modified_index:uint [, timeout:uint] ])`


- `modified_index`: uint - this argument to use to the `prev_index` query of atomic operation.
- `timeout`: uint - request timeout seconds. set 0 to disable timeout.

```lua
local res, err = cli:waitdir('/path/to/dir')
```

[Back to TOP](#api-v2)

### push

`syntax: res, err = cli:push(dir:string, val:JSON value [, ttl:int])`

Pushs a value into the specified directory.

```lua
local res, err = cli:mkdir('/path/to/dir')
res, err = cli:push('/path/to/dir', 'val', 10)
```

[Back to TOP](#api-v2)

### version

`syntax: res, err = cli:version()`

Gets the etcd version info.

[Back to TOP](#api-v2)

### stats_leader

`syntax: res, err = cli:stats_leader()`

Gets the leader statistics info.

[Back to TOP](#api-v2)

### stats_self

`syntax: res, err = cli:stats_self()`

Gets the self statistics info.

[Back to TOP](#api-v2)

### stats_store

`syntax: res, err = cli:stats_store()`

Gets the store statistics info.

[Back to TOP](#api-v2)
