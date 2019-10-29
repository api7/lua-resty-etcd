API V3
======

* [Methods](#methods)
    * [new](#new)
    * [get](#get)
    * [set](#set)

Method
======

### new

`syntax: cli, err = etcd.new([option:table])`

- `option:table`
  - `protocol`: string - `v3`.
  - `http_host`: string - default `http://127.0.0.1:2379`
  - `ttl`: int - default `-1`
    default ttl for key operation. set -1 to disable ttl.
  - `prefix`: string
    append this prefix path string to key operation url.
  - `timeout`: int
    request timeout seconds.

The client methods returns either a `etcd` object or an `error string`.

```lua
local cli, err = require("resty.etcd").new({prototol = "v3"})
```

Please refer the **etcd API documentaion** at - https://github.com/coreos/etcd for more details.

[Back to TOP](#api-v3)

### get

`syntax: res, err = cli:get(key:string[, opts])`

* `key`: string value.
* `opts`: optional options.
    * `timeout`: the timeout to fetch the value of specified `key`.
    * `revision`: revision value.

Gets the value for key.

```lua
local res, err = cli:get('/path_/to/_key')
```

[Back to TOP](#api-v3)

### set

`syntax: res, err = cli:set(key:string, val:JSON value [, opts])`

* `key`: string value.
* `val`: the value which can be encoded via JSON.
* `opts`: optional options.
    * `timeout`: the timeout to fetch the value of specified `key`.
    * `lease`: lease value.
    * `prev_kv`: prev_kv value.
    * `ignore_value`: ignore_value value.
    * `ignore_lease`: ignore_lease value.

Set a key-value pair.

```lua
local res, err = cli:set('/path/to/key', 'val', 10)
```

[Back to TOP](#api-v3)
