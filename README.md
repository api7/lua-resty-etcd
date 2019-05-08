lua-resty-etcd
==============

[etcd](https://github.com/membphis/lua-resty-etcd) client module under OpenResty, this module supports etcd API v2.

---

## Dependencies

- lua-resty-http: https://github.com/ledgetech/lua-resty-http

```shell
luarocks install lua-resty-http
```

## Create client object

#### cli, err = Etcd.new([option:table])

```lua
local cli, err = require('resty.etcd').new()
```

**Parameters**

- `option:table`
  - `host`: string - default `http://127.0.0.1:2379`
  - `ttl`: int - default `-1`
    default ttl for key operation. set -1 to disable ttl.
  - `prefix`: string
    append this prefix path string to key operation url `'/v2/keys'`.
  - `timeout`: int
    request timeout seconds.


**Returns**

1. `cli`: client object.
2. `err`: error string.


## About the return values of client methods.

client methods returns either a `HTTP Response Entity` or an `error string`.

a `HTTP Response Entity` contains the following fields except `408` timeout status;

- `status`: number - HTTP status code.
- `header`: table - response header if `status` is not `408` timeout status.
- `body`: string or table - response body if `status` is not `408` timeout status.

**Note:** a client method will decode a response body as a JSON string if a `Content-Type` response header value is a `application/json`.


please refer the **etcd API documentaion** at - https://github.com/coreos/etcd for more details of a response entity.


## Key-value operations

### Get the key-value pair

#### res, err = cli:get(key:string)

get the value for key.

```lua
local res, err = cli:get('/path/to/key')
```

### Set the key-value pair

#### res, err = cli:set(key:string, val:JSON encodable value [, ttl:int])

set a key-value pair.

```lua
local res, err = cli:set('/path/to/key', 'val', 10)
```

#### res, err = cli:setnx(key:string, val:JSON encodable value [, ttl:int])

set a key-value pair if that key does not exist.

```lua
local res, err = cli:setnx('/path/to/key', 'val', 10)
```


#### res, err = cli:setx(key:string, val:JSON encodable value [, ttl:int [, modifiedIndex:uint] ])

set a key-value pair when that key is exists.

```lua
local res, err = cli:setx('/path/to/key', 'val', 10)
```

**Parameters**

- `modifiedIndex`: uint - this argument to use to the `prevIndex` query of atomic operation.

```lua
local res, err = cli:get('/path/to/key')

-- this operation will be failed if the `modifiedIndex` of specified key has already been updated by another client.
res, err = cli:setx('/path/to/key', 'val', 10, res.body.node.modifiedIndex)
```


### Delete the key-value pair

#### res, err = cli:delete(key:string [, val:JSON encodable value [, modifiedIndex:uint] ])

delete a key-value pair.

```lua
local res, err = cli:delete('/path/to/key')
```

**Parameters**

- `val`: JSON encodable value - this argument to use to the `prevValue` query of atomic operation.
- `modifiedIndex`: uint - this argument to use to the `prevIndex` query of atomic operation.

```lua
local res, err = cli:get('/path/to/key')

-- delete key-value pair if both of `value` and `modifiedIndex` has matched to the passed arguments
res, err = cli:delete('/path/to/key', res.body.node.value, res.body.node.modifiedIndex)

-- delete key-value pair if `value` has matched to the passed value
res, err = cli:delete('/path/to/key', res.body.node.value)

-- delete key-value pair if `modifiedIndex` has matched to the passed modifiedIndex
res, err = cli:delete('/path/to/key', nil, res.body.node.modifiedIndex)

```


### Wait the update of key.

#### res, err = cli:wait(key:string [, modifiedIndex:uint [, timeout:uint] ])

```lua
local res, err = cli:wait('/path/to/key')
```

**Parameters**

- `modifiedIndex`: uint - this argument to use to the `prevIndex` query of atomic operation.
- `timeout`: uint - request timeout seconds. set 0 to disable timeout.

```lua

local res, err = cli:get('/path/to/key')

-- Wait forever the update of key until that modifiedIndex of key has changed to modifiedIndex + 1
res, err = cli:wait('/path/to/key', res.body.node.modifiedIndex + 1, 0)

-- Wait for 10 seconds the update of key until that modifiedIndex of key has changed to modifiedIndex + 2
res, err = cli:wait('/path/to/key', res.body.node.modifiedIndex + 2, 10)


```


## Directory operations

### Read the directory

#### res, err = cli:readdir(key:string [, recursive:boolean])

```lua
local res, err = cli:readdir('/path/to/dir')
```

**Parameters**

- `recursive`: boolean - get all the contents under a directory.


### Create the directory

#### res, err = cli:mkdir(key:string [, ttl:int])

create a directory.

```lua
local res, err = cli:mkdir('/path/to/dir', 10)
```

#### res, err = cli:mkdirnx(key:string [, ttl:int])

create a directory if that directory does not exist.

```lua
local res, err = cli:mkdirnx('/path/to/dir', 10)
```

### Remove the directory

#### res, err = cli:rmdir(key:string [, recursive:boolean])

```lua
local res, err = cli:rmdir('/path/to/dir')
```

**Parameters**

- `recursive`: boolean - remove all the contents under a directory.


### Wait the update of directory

#### res, err = cli:waitdir(key:string [, modifiedIndex:uint [, timeout:uint] ])

```lua
local res, err = cli:waitdir('/path/to/dir')
```

**Parameters**

- `modifiedIndex`: uint - this argument to use to the `prevIndex` query of atomic operation.
- `timeout`: uint - request timeout seconds. set 0 to disable timeout.


### Push a value into the directory


#### res, err = cli:push(key:string, val:JSON encodable value [, ttl:int])

push a value into the specified directory.

```lua
local res, err = cli:mkdir('/path/to/dir')
res, err = cli:push('/path/to/dir', 'val', 10)
```


## Get or set the cluster information

the following client methods to use to get or set the cluster informations.

### Get the etcd version

#### res, err = cli:version()

getting the etcd version info.

```lua
local res, err = cli:version()
```

### Get the cluster statistics

the following client methods to use to get the cluster statistics information.

#### res, err = cli:statsLeader()

getting the leader statistics info.

```lua
local res, err = cli:statsLeader()
```

#### res, err = cli:statsSelf()

getting the self statistics info.

```lua
local res, err = cli:statsSelf()
```

#### res, err = cli:statsStore()

getting the store statistics info.

```lua
local res, err = cli:statsSelf()
```
