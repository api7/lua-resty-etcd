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
    * [watchdir](#watchdir)
    * [readdir](#readdir)
    * [watchdir](#watchdir)
    * [rmdir](#rmdir)
    * [txn](#txn)
    * [version](#version)

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
    to suit [etcd v3 api gateway](https://github.com/etcd-io/etcd/blob/master/Documentation/dev-guide/api_grpc_gateway.md#notes).
    it will autofill by fetching etcd version if this option empty.

The client methods returns either a `etcd` object or an `error string`.

```lua
local cli, err = require("resty.etcd").new({protocol = "v3"})
```

Please refer the **etcd API documentaion** at - https://github.com/coreos/etcd for more details.

[Back to TOP](#api-v3)

### get

`syntax: res, err = cli:get(key:string[, opts])`

* `key`: string value.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. set 0 to disable timeout.
    * `revision`: (int) revision is the point-in-time of the key-value store to use for the range. If revision is less or equal to zero, the range is over the newest key-value store. If the revision has been compacted, ErrCompacted is returned as a response.

Gets the value for key.

```lua
local res, err = cli:get('/path_/to/_key')
```

[Back to TOP](#api-v3)

### set

`syntax: res, err = cli:set(key:string, val:JSON value [, opts:table])`

* `key`: string value.
* `val`: the value which can be encoded via JSON.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. set 0 to disable timeout.
    * `lease`: (int) the lease ID to associate with the key in the key-value store.
    * `prev_kv`: (bool) If prev_kv is set, etcd gets the previous key-value pair before changing it. The previous key-value pair will be returned in the put response.
    * `ignore_value`: (bool) If ignore_value is set, etcd updates the key using its current value. Returns an error if the key does not exist. 
    * `ignore_lease`: (bool) If ignore_lease is set, etcd updates the key using its current lease. Returns an error if the key does not exist.

Set a key-value pair.

```lua
local res, err = cli:set('/path/to/key', 'val', 10)
```

[Back to TOP](#api-v3)

### setnx

`syntax: res, err = cli:setnx(key:string, val:JSON value [, opts:table])`

* `key`: string value.
* `val`: the value which can be encoded via JSON.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. set 0 to disable timeout.

Set a key-value pair if that key does not exist.

```lua
local res, err = cli:setnx('/path/to/key', 'val', 10)
```

[Back to TOP](#api-v3)

### setx

`syntax: res, err = cli:setx(key:string, val:JSON value [, opts:table])`

* `key`: string value.
* `val`: the value which can be encoded via JSON.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. set 0 to disable timeout.

Set a key-value pair when that key is exists.

```lua
local res, err = cli:setx('/path/to/key', 'val', 10)
```

[Back to TOP](#api-v3)

### delete

`syntax: res, err = cli:delete(key:string [, opts:table])`

* `key`: string value.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. set 0 to disable timeout.
    * `prev_kv`: (bool) If prev_kv is set, etcd gets the previous key-value pairs before deleting it. The previous key-value pairs will be returned in the delete response.

Deletes a key-value pair.

```lua
local res, err = cli:delete('/path/to/key')
```

[Back to TOP](#api-v3)


### watch

`syntax: res, err = cli:watch(key:string [, opts:table]) `

* `key`: string value.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. set 0 to disable timeout.
    * `start_revision`: (int) start_revision is an optional revision to watch from (inclusive). No start_revision is "now".
    * `progress_notify`: (bool) progress_notify is set so that the etcd server will periodically send a WatchResponse with no events to the new watcher if there are no recent events. 
    * `filters`: (slice of (enum FilterType {NOPUT = 0;NODELETE = 1;})) filters filter the events at server side before it sends back to the watcher.  
    * `prev_kv`: (bool) If prev_kv is set, created watcher gets the previous KV before the event happens. If the previous KV is already compacted, nothing will be returned.
    * `watch_id`: (int) If watch_id is provided and non-zero, it will be assigned to this watcher. Since creating a watcher in etcd is not a synchronous operation, this can be used ensure that ordering is correct when creating multiple watchers on the same stream. Creating a watcher with an ID already in use on the stream will cause an error to be returned. 
    * `fragment`: (bool) fragment enables splitting large revisions into multiple watch responses.  

Watch the update of key.

```lua
local res, err = cli:watch('/path/to/key')
```

[Back to TOP](#api-v3)

### readdir

`syntax: res, err = cli:readdir(key:string [, opts:table])`

* `key`: string value.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. set 0 to disable timeout.
    * `revision`: (int) revision is the point-in-time of the key-value store to use for the range. If revision is less or equal to zero, the range is over the newest key-value store. If the revision has been compacted, ErrCompacted is returned as a response.
    * `limit`: (int) limit is a limit on the number of keys returned for the request. When limit is set to 0, it is treated as no limit. 
    * `sort_order`: (int [SortNone:0, SortAscend:1, SortDescend:2]) sort_order is the order for returned sorted results.  
    * `sort_target`: (int [SortByKey:0, SortByVersion:1, SortByCreateRevision:2, SortByModRevision:3, SortByValue:4]) sort_target is the key-value field to use for sorting.
    * `keys_only`: (bool) keys_only when set returns only the keys and not the values.  
    * `count_only`: (bool) count_only when set returns only the count of the keys in the range. 

Read the directory.

```lua
local res, err = cli:readdir('/path/to/dir')
```

[Back to TOP](#api-v3)


### watchdir

`syntax: res, err = cli:watchdir(key:string [, opts:table])`


* `key`: string value.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. set 0 to disable timeout.
    * `start_revision`: (int) start_revision is an optional revision to watch from (inclusive). No start_revision is "now".
    * `progress_notify`: (bool) progress_notify is set so that the etcd server will periodically send a WatchResponse with no events to the new watcher if there are no recent events. 
    * `filters`: (slice of [enum FilterType {NOPUT = 0;NODELETE = 1;}]) filters filter the events at server side before it sends back to the watcher.  
    * `prev_kv`: (bool) If prev_kv is set, created watcher gets the previous KV before the event happens. If the previous KV is already compacted, nothing will be returned.
    * `watch_id`: (int) If watch_id is provided and non-zero, it will be assigned to this watcher. Since creating a watcher in etcd is not a synchronous operation, this can be used ensure that ordering is correct when creating multiple watchers on the same stream. Creating a watcher with an ID already in use on the stream will cause an error to be returned. 
    * `fragment`: (bool) fragment enables splitting large revisions into multiple watch responses.  

Watch the update of directory.


```lua
local res, err = cli:watchdir('/path/to/dir')
```

[Back to TOP](#api-v3)


### rmdir

`syntax: res, err = cli:rmdir(key:string [, opts:table])`

* `key`: string value.
* `opts`: optional options.
    * `timeout`: (int) request timeout seconds. set 0 to disable timeout.
    * `prev_kv`: (bool) If prev_kv is set, etcd gets the previous key-value pairs before deleting it. The previous key-value pairs will be returned in the delete response.

Remove the directory

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
    * `timeout`: (int) request timeout seconds. set 0 to disable timeout.

Transaction

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

Gets the etcd version info.

[Back to TOP](#api-v3)
