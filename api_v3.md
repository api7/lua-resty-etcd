API V3
======

* [Methods](#methods)
    * [new](#new)
    * [get](#get)
    * [set](#set)
    * [setnx](#setnx)
    * [setx](#setx)
    * [delete](#delete)
    * [watch](#watch)
    * [watchcancel](#watchcancel)
    * [readdir](#readdir)
    * [watchdir](#watchdir)
    * [rmdir](#rmdir)
    * [txn](#txn)
    * [version](#version)
    * [grant](#grant)
    * [revoke](#revoke)
    * [keepalive](#keepalive)
    * [timetolive](#timetolive)
    * [leases](#leases)

Method
======

### new

`syntax: cli, err = etcd.new([option:table])`

- `option:table`
  - `protocol`: string - `v3`.
  - `http_host`: string - default `http://127.0.0.1:2379`
  - `ttl`: int - default `-1`
    default ttl for key operation. set -1 to disable ttl.
  - `key_prefix`: string
    append this prefix path string to key operation url.
  - `timeout`: int
    default request timeout seconds.
  - `api_prefix`: string
    to suit [etcd v3 api gateway](https://etcd.io/docs/v3.5/dev-guide/api_grpc_gateway/#notes).
    it will autofill by fetching etcd version if this option empty.
  - `ssl_verify`: boolean - whether to verify the etcd certificate when originating TLS connection with etcd (if you want to communicate to etcd with TLS connection, use `https` scheme in your `http_host`), default is `true`.
  - `ssl_cert_path`： string - path to the client certificate
  - `ssl_key_path`： string - path to the client key
  - `serializer`: string - serializer type, default `json`, also support `raw` to keep origin string value.
  - `extra_headers`: table - adding custom headers for etcd requests.
  - `sni`: string - adding custom SNI fot etcd TLS requests.
  - `unix_socket_proxy`: string - the unix socket path which will be used to proxy the etcd request.

The client method returns either a `etcd` object or an `error string`.

```lua
local cli, err = require("resty.etcd").new({protocol = "v3"})
```

Please refer to the **etcd API documentaion** at - https://github.com/coreos/etcd for more details.

[Back to TOP](#api-v3)

### get

`syntax: res, err = cli:get(key:string[, opts])`

* `key`: string value.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. Set to 0 would use `lua_socket_connect_timeout` as timeout.
    * `revision`: (int) revision is the point-in-time of the key-value store to use for the range. If revision is less than or equal to zero, the range is over the newest key-value store. If the revision has been compacted, ErrCompacted is returned as a response.

To get the value for key.

```lua
local res, err = cli:get('/path/to/key')
```

[Back to TOP](#api-v3)

### set

`syntax: res, err = cli:set(key:string, val:JSON value [, opts:table])`

* `key`: string value.
* `val`: the value which can be encoded via JSON.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. Set to 0 would use `lua_socket_connect_timeout` as timeout.
    * `lease`: (int) the lease ID to associate with the key in the key-value store.
    * `prev_kv`: (bool) If prev_kv is set, etcd gets the previous key-value pair before changing it. The previous key-value pair will be returned in the put response.
    * `ignore_value`: (bool) If ignore_value is set, etcd updates the key using its current value. Returns an error if the key does not exist. 
    * `ignore_lease`: (bool) If ignore_lease is set, etcd updates the key using its current lease. Returns an error if the key does not exist.

To set a key-value pair.

```lua
local res, err = cli:set('/path/to/key', 'val', 10)
```

[Back to TOP](#api-v3)

### setnx

`syntax: res, err = cli:setnx(key:string, val:JSON value [, opts:table])`

* `key`: string value.
* `val`: the value which can be encoded via JSON.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. Set to 0 would use `lua_socket_connect_timeout` as timeout.

To set a key-value pair if that key does not exist.

```lua
local res, err = cli:setnx('/path/to/key', 'val', 10)
```

[Back to TOP](#api-v3)

### setx

`syntax: res, err = cli:setx(key:string, val:JSON value [, opts:table])`

* `key`: string value.
* `val`: the value which can be encoded via JSON.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. Set to 0 would use `lua_socket_connect_timeout` as timeout.

To set a key-value pair when that key exists.

```lua
local res, err = cli:setx('/path/to/key', 'val', 10)
```

[Back to TOP](#api-v3)

### delete

`syntax: res, err = cli:delete(key:string [, opts:table])`

* `key`: string value.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. Set to 0 would use `lua_socket_connect_timeout` as timeout.
    * `prev_kv`: (bool) If prev_kv is set, etcd gets the previous key-value pairs before deleting it. The previous key-value pairs will be returned in the delete response.

To delete a key-value pair.

```lua
local res, err = cli:delete('/path/to/key')
```

[Back to TOP](#api-v3)


### watch

`syntax: res, err = cli:watch(key:string [, opts:table]) `

* `key`: string value.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. Set to 0 would use `lua_socket_connect_timeout` as timeout.
    * `start_revision`: (int) start_revision is an optional revision to watch from (inclusive). No start_revision is "now".
    * `progress_notify`: (bool) progress_notify is set so that the etcd server will periodically send a WatchResponse with no events to the new watcher if there are no recent events. 
    * `filters`: (slice of (enum FilterType {NOPUT = 0;NODELETE = 1;})) filters filter the events at server side before it sends back to the watcher.  
    * `prev_kv`: (bool) If prev_kv is set, created watcher gets the previous KV before the event happens. If the previous KV is already compacted, nothing will be returned.
    * `watch_id`: (int) If watch_id is provided and non-zero, it will be assigned to this watcher. Since creating a watcher in etcd is not a synchronous operation, this can be used to ensure that ordering is correct when creating multiple watchers on the same stream. Creating a watcher with an ID already in use on the stream will cause an error to be returned. 
    * `fragment`: (bool) fragment enables splitting large revisions into multiple watch responses.  
    * `need_cancel`: (bool) if watch need to be cancel, watch would return http_cli for further cancelation. See [watchcancel](#watchcancel) for detail.

To watch the update of key.

```lua
local res, err = cli:watch('/path/to/key')
```

[Back to TOP](#api-v3)

### watchcancel

`syntax: res, err = cli:watchcancel(http_cli:table)`

* `http_cli`: the http client needs to revoke.

To cancel the watch before it get expired. Need to set `need_cancel` to get the http client for cancelation.

```lua
local res, err, http_cli = cli:watch('/path/to/key', {need_cancel = true})
res = cli:watchcancel(http_cli)
```

[Back to TOP](#api-v3)

### readdir

`syntax: res, err = cli:readdir(dir:string [, opts:table])`

* `key`: string value.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. Set to 0 would use `lua_socket_connect_timeout` as timeout.
    * `revision`: (int) revision is the point-in-time of the key-value store to use for the range. If revision is less than or equal to zero, the range is over the newest key-value store. If the revision has been compacted, ErrCompacted is returned as a response.
    * `limit`: (int) limit is a limit on the number of keys returned for the request. When limit is set to 0, it is treated as no limit. 
    * `sort_order`: (int [SortNone:0, SortAscend:1, SortDescend:2]) sort_order is the order for returned sorted results.  
    * `sort_target`: (int [SortByKey:0, SortByVersion:1, SortByCreateRevision:2, SortByModRevision:3, SortByValue:4]) sort_target is the key-value field to use for sorting.
    * `keys_only`: (bool) keys_only when set returns only the keys and not the values.  
    * `count_only`: (bool) count_only when set returns only the count of the keys in the range. 

To read the directory.

```lua
local res, err = cli:readdir('/path/to/dir')
```

[Back to TOP](#api-v3)


### watchdir

`syntax: res, err = cli:watchdir(dir:string [, opts:table])`


* `key`: string value.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. Set to 0 would use `lua_socket_connect_timeout` as timeout.
    * `start_revision`: (int) start_revision is an optional revision to watch from (inclusive). No start_revision is "now".
    * `progress_notify`: (bool) progress_notify is set so that the etcd server will periodically send a WatchResponse with no events to the new watcher if there are no recent events. 
    * `filters`: (slice of [enum FilterType {NOPUT = 0;NODELETE = 1;}]) filters filter the events at server side before it sends back to the watcher.  
    * `prev_kv`: (bool) If prev_kv is set, created watcher gets the previous KV before the event happens. If the previous KV is already compacted, nothing will be returned.
    * `watch_id`: (int) If watch_id is provided and non-zero, it will be assigned to this watcher. Since creating a watcher in etcd is not a synchronous operation, this can be used to ensure that ordering is correct when creating multiple watchers on the same stream. Creating a watcher with an ID already in use on the stream will cause an error to be returned. 
    * `fragment`: (bool) fragment enables splitting large revisions into multiple watch responses.  

To watch the update of directory.


```lua
local res, err = cli:watchdir('/path/to/dir')
```

[Back to TOP](#api-v3)


### rmdir

`syntax: res, err = cli:rmdir(dir:string [, opts:table])`

* `key`: string value.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. Set to 0 would use `lua_socket_connect_timeout` as timeout.
    * `prev_kv`: (bool) If prev_kv is set, etcd gets the previous key-value pairs before deleting it. The previous key-value pairs will be returned in the delete response.

To remove the directory.

```lua
local res, err = cli:rmdir('/path/to/dir')
```

[Back to TOP](#api-v3)


### txn

`syntax: res, err = cli:txn(compare:array, success:array, failure:array [, opts:table])`

* `compare`: array of [table](https://github.com/etcd-io/etcd/blob/master/Documentation/dev-guide/api_reference_v3.md#message-compare-etcdserveretcdserverpbrpcproto).
* `success`: array of [table](https://github.com/etcd-io/etcd/blob/master/Documentation/dev-guide/api_reference_v3.md#message-requestop-etcdserveretcdserverpbrpcproto).
* `failure`: array of [table](https://github.com/etcd-io/etcd/blob/master/Documentation/dev-guide/api_reference_v3.md#message-requestop-etcdserveretcdserverpbrpcproto).
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. Set to 0 would use `lua_socket_connect_timeout` as timeout.

Transaction.

```lua
local compare = {}
compare[1] = {}
compare[1].target = "CREATE"
compare[1].key    = encode_base64("test")
compare[1].createRevision = 0

local success = {}
success[1] = {}
success[1].requestPut = {}
success[1].requestPut.key = encode_base64("test")

local res, err = cli:txn(compare, success, nil)
```

[Back to TOP](#api-v3)


### version

`syntax: res, err = cli:version()`

To get the etcd version info.

[Back to TOP](#api-v3)

### grant

`syntax: res, err = cli:grant(TTL:int [, ID:int])`

- `TTL`: advisory time-to-live in seconds.
- `ID`: the requested ID for the lease. If ID is set to 0, the lessor chooses an ID.

To create a lease which expires if the server does not receive a keepalive within a given time to live period. All keys attached to the lease will get expired and be deleted if the lease expires. Each expired key generates a delete event in the event history.

```lua
-- grant a lease with 5 second TTL
local res, err = cli:grant(5)

-- attach key to lease, whose ID would be contained in res
local data, err = etcd:set('/path/to/key', 'val', {lease = res.body.ID})
```

[Back to TOP](#api-v3)

### revoke

`syntax: res, err = cli:revoke(ID:int)`

- `ID`: the lease ID to revoke. When the ID is revoked, all associated keys will be deleted.

To revoke a lease. All keys attached to the lease will expire and be deleted.

```lua
local res, err = cli:grant(5)
local data, err = etcd:set('/path/to/key', 'val', {lease = res.body.ID})

local data, err = etcd:revoke(res.body.ID)
local data, err = cli:get('/path/to/key')
-- responce would contains no kvs
```

[Back to TOP](#api-v3)

### keepalive

`syntax: res, err = cli:keepalive(ID:int)`

- `ID`: the lease ID for the lease to keep alive.

To keep the lease alive by streaming keep alive requests from the client to the server and streaming keep alive responses from the server to the client.

[Back to TOP](#api-v3)

### timetolive

`syntax: res, err = cli:timetolive(ID:int [, keys: bool])`

- `ID`: the lease ID for the lease.
- `keys`: if true, query all the keys attached to this lease.

To retrieve lease information.

[Back to TOP](#api-v3)

### leases

`syntax: res, err = cli:leases()`

To list all existing leases.

[Back to TOP](#api-v3)

