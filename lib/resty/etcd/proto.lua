return [[
// this proto file is copied from https://github.com/etcd-io/etcd under Apache 2.0 License
// only copy the services / fields used by APISIX
syntax = "proto3";
package etcdserverpb;

service KV {
  // Range gets the keys in the range from the key-value store.
  rpc Range(RangeRequest) returns (RangeResponse) {}
  // Put puts the given key into the key-value store.

  // A put request increments the revision of the key-value store
  // and generates one event in the event history.
  rpc Put(PutRequest) returns (PutResponse) {}

  // DeleteRange deletes the given range from the key-value store.
  // A delete request increments the revision of the key-value store
  // and generates a delete event in the event history for every deleted key.
  rpc DeleteRange(DeleteRangeRequest) returns (DeleteRangeResponse) {}

  // Txn processes multiple requests in a single transaction.
  // A txn request increments the revision of the key-value store
  // and generates events with the same revision for every completed request.
  // It is not allowed to modify the same key several times within one txn.
  rpc Txn(TxnRequest) returns (TxnResponse) {}
}

message ResponseHeader {
  // cluster_id is the ID of the cluster which sent the response.
  uint64 cluster_id = 1;
  // member_id is the ID of the member which sent the response.
  uint64 member_id = 2;
  // revision is the key-value store revision when the request was applied.
  // For watch progress responses, the header.revision indicates progress. All future events
  // recieved in this stream are guaranteed to have a higher revision number than the
  // header.revision number.
  int64 revision = 3;
  // raft_term is the raft term when the request was applied.
  uint64 raft_term = 4;
}

message RangeRequest {
  enum SortOrder {
	NONE = 0; // default, no sorting
	ASCEND = 1; // lowest target value first
	DESCEND = 2; // highest target value first
  }
  enum SortTarget {
	KEY = 0;
	VERSION = 1;
	CREATE = 2;
	MOD = 3;
	VALUE = 4;
  }

  // key is the first key for the range. If range_end is not given, the request only looks up key.
  bytes key = 1;
  // range_end is the upper bound on the requested range [key, range_end).
  // If range_end is '\0', the range is all keys >= key.
  // If range_end is key plus one (e.g., "aa"+1 == "ab", "a\xff"+1 == "b"),
  // then the range request gets all keys prefixed with key.
  // If both key and range_end are '\0', then the range request returns all keys.
  bytes range_end = 2;
  // limit is a limit on the number of keys returned for the request. When limit is set to 0,
  // it is treated as no limit.
  int64 limit = 3;
  // revision is the point-in-time of the key-value store to use for the range.
  // If revision is less or equal to zero, the range is over the newest key-value store.
  // If the revision has been compacted, ErrCompacted is returned as a response.
  int64 revision = 4;

  // sort_order is the order for returned sorted results.
  SortOrder sort_order = 5;

  // sort_target is the key-value field to use for sorting.
  SortTarget sort_target = 6;

  // serializable sets the range request to use serializable member-local reads.
  // Range requests are linearizable by default; linearizable requests have higher
  // latency and lower throughput than serializable requests but reflect the current
  // consensus of the cluster. For better performance, in exchange for possible stale reads,
  // a serializable range request is served locally without needing to reach consensus
  // with other nodes in the cluster.
  bool serializable = 7;

  // keys_only when set returns only the keys and not the values.
  bool keys_only = 8;

  // count_only when set returns only the count of the keys in the range.
  bool count_only = 9;

  // min_mod_revision is the lower bound for returned key mod revisions; all keys with
  // lesser mod revisions will be filtered away.
  int64 min_mod_revision = 10;

  // max_mod_revision is the upper bound for returned key mod revisions; all keys with
  // greater mod revisions will be filtered away.
  int64 max_mod_revision = 11;

  // min_create_revision is the lower bound for returned key create revisions; all keys with
  // lesser create revisions will be filtered away.
  int64 min_create_revision = 12;

  // max_create_revision is the upper bound for returned key create revisions; all keys with
  // greater create revisions will be filtered away.
  int64 max_create_revision = 13;
}

message KeyValue {
  // key is the key in bytes. An empty key is not allowed.
  bytes key = 1;
  // create_revision is the revision of last creation on this key.
  int64 create_revision = 2;
  // mod_revision is the revision of last modification on this key.
  int64 mod_revision = 3;
  // version is the version of the key. A deletion resets
  // the version to zero and any modification of the key
  // increases its version.
  int64 version = 4;
  // value is the value held by the key, in bytes.
  bytes value = 5;
  // lease is the ID of the lease that attached to key.
  // When the attached lease expires, the key will be deleted.
  // If lease is 0, then no lease is attached to the key.
  int64 lease = 6;
}

message RangeResponse {
  ResponseHeader header = 1;
  // kvs is the list of key-value pairs matched by the range request.
  // kvs is empty when count is requested.
  repeated KeyValue kvs = 2;
  // more indicates if there are more keys to return in the requested range.
  bool more = 3;
  // count is set to the number of keys within the range when requested.
  int64 count = 4;
}

message PutRequest {
  // key is the key, in bytes, to put into the key-value store.
  bytes key = 1;
  // value is the value, in bytes, to associate with the key in the key-value store.
  bytes value = 2;
  // lease is the lease ID to associate with the key in the key-value store. A lease
  // value of 0 indicates no lease.
  int64 lease = 3;

  // If prev_kv is set, etcd gets the previous key-value pair before changing it.
  // The previous key-value pair will be returned in the put response.
  bool prev_kv = 4;

  // If ignore_value is set, etcd updates the key using its current value.
  // Returns an error if the key does not exist.
  bool ignore_value = 5;

  // If ignore_lease is set, etcd updates the key using its current lease.
  // Returns an error if the key does not exist.
  bool ignore_lease = 6;
}

message PutResponse {
  ResponseHeader header = 1;
  // if prev_kv is set in the request, the previous key-value pair will be returned.
  KeyValue prev_kv = 2;
}

message DeleteRangeRequest {
  // key is the first key to delete in the range.
  bytes key = 1;
  // range_end is the key following the last key to delete for the range [key, range_end).
  // If range_end is not given, the range is defined to contain only the key argument.
  // If range_end is one bit larger than the given key, then the range is all the keys
  // with the prefix (the given key).
  // If range_end is '\0', the range is all keys greater than or equal to the key argument.
  bytes range_end = 2;

  // If prev_kv is set, etcd gets the previous key-value pairs before deleting it.
  // The previous key-value pairs will be returned in the delete response.
  bool prev_kv = 3;
}

message DeleteRangeResponse {
  ResponseHeader header = 1;
  // deleted is the number of keys deleted by the delete range request.
  int64 deleted = 2;
  // if prev_kv is set in the request, the previous key-value pairs will be returned.
  repeated KeyValue prev_kvs = 3;
}

message RequestOp {
  // request is a union of request types accepted by a transaction.
  oneof request {
    RangeRequest request_range = 1;
    PutRequest request_put = 2;
    DeleteRangeRequest request_delete_range = 3;
    TxnRequest request_txn = 4;
  }
}

message ResponseOp {
  // response is a union of response types returned by a transaction.
  oneof response {
    RangeResponse response_range = 1;
    PutResponse response_put = 2;
    DeleteRangeResponse response_delete_range = 3;
    TxnResponse response_txn = 4;
  }
}

message Compare {
  enum CompareResult {
    EQUAL = 0;
    GREATER = 1;
    LESS = 2;
    NOT_EQUAL = 3;
  }
  enum CompareTarget {
    VERSION = 0;
    CREATE = 1;
    MOD = 2;
    VALUE = 3;
    LEASE = 4;
  }
  // result is logical comparison operation for this comparison.
  CompareResult result = 1;
  // target is the key-value field to inspect for the comparison.
  CompareTarget target = 2;
  // key is the subject key for the comparison operation.
  bytes key = 3;
  oneof target_union {
    // version is the version of the given key
    int64 version = 4;
    // create_revision is the creation revision of the given key
    int64 create_revision = 5;
    // mod_revision is the last modified revision of the given key.
    int64 mod_revision = 6;
    // value is the value of the given key, in bytes.
    bytes value = 7;
    // lease is the lease id of the given key.
    int64 lease = 8;
    // leave room for more target_union field tags, jump to 64
  }

  // range_end compares the given target to all keys in the range [key, range_end).
  // See RangeRequest for more details on key ranges.
  bytes range_end = 64;
  // TODO: fill out with most of the rest of RangeRequest fields when needed.
}

message TxnRequest {
  // compare is a list of predicates representing a conjunction of terms.
  // If the comparisons succeed, then the success requests will be processed in order,
  // and the response will contain their respective responses in order.
  // If the comparisons fail, then the failure requests will be processed in order,
  // and the response will contain their respective responses in order.
  repeated Compare compare = 1;
  // success is a list of requests which will be applied when compare evaluates to true.
  repeated RequestOp success = 2;
  // failure is a list of requests which will be applied when compare evaluates to false.
  repeated RequestOp failure = 3;
}

message TxnResponse {
  ResponseHeader header = 1;
  // succeeded is set to true if the compare evaluated to true or false otherwise.
  bool succeeded = 2;
  // responses is a list of responses corresponding to the results from applying
  // success if succeeded is true or failure if succeeded is false.
  repeated ResponseOp responses = 3;
}

message Event {
  enum EventType {
    PUT = 0;
    DELETE = 1;
  }
  // type is the kind of event. If type is a PUT, it indicates
  // new data has been stored to the key. If type is a DELETE,
  // it indicates the key was deleted.
  EventType type = 1;
  // kv holds the KeyValue for the event.
  // A PUT event contains current kv pair.
  // A PUT event with kv.Version=1 indicates the creation of a key.
  // A DELETE/EXPIRE event contains the deleted key with
  // its modification revision set to the revision of deletion.
  KeyValue kv = 2;

  // prev_kv holds the key-value pair before the event happens.
  KeyValue prev_kv = 3;
}

message WatchRequest {
  // request_union is a request to either create a new watcher or cancel an existing watcher.
  oneof request_union {
    WatchCreateRequest create_request = 1;
    WatchCancelRequest cancel_request = 2;
    WatchProgressRequest progress_request = 3;
  }
}

message WatchCreateRequest {
  // key is the key to register for watching.
  bytes key = 1;

  // range_end is the end of the range [key, range_end) to watch. If range_end is not given,
  // only the key argument is watched. If range_end is equal to '\0', all keys greater than
  // or equal to the key argument are watched.
  // If the range_end is one bit larger than the given key,
  // then all keys with the prefix (the given key) will be watched.
  bytes range_end = 2;

  // start_revision is an optional revision to watch from (inclusive). No start_revision is "now".
  int64 start_revision = 3;
}

message WatchCancelRequest {
  // watch_id is the watcher id to cancel so that no more events are transmitted.
  int64 watch_id = 1;
}

// Requests the a watch stream progress status be sent in the watch response stream as soon as
// possible.
message WatchProgressRequest {
}

message WatchResponse {
  ResponseHeader header = 1;
  // watch_id is the ID of the watcher that corresponds to the response.
  int64 watch_id = 2;

  // created is set to true if the response is for a create watch request.
  // The client should record the watch_id and expect to receive events for
  // the created watcher from the same stream.
  // All events sent to the created watcher will attach with the same watch_id.
  bool created = 3;

  // canceled is set to true if the response is for a cancel watch request.
  // No further events will be sent to the canceled watcher.
  bool canceled = 4;

  // compact_revision is set to the minimum index if a watcher tries to watch
  // at a compacted index.
  //
  // This happens when creating a watcher at a compacted revision or the watcher cannot
  // catch up with the progress of the key-value store.
  //
  // The client should treat the watcher as canceled and should not try to create any
  // watcher with the same start_revision again.
  int64 compact_revision = 5;

  // cancel_reason indicates the reason for canceling the watcher.
  string cancel_reason = 6;

  // framgment is true if large watch response was split over multiple responses.
  bool fragment = 7;

  repeated Event events = 11;
}

service Watch {
  // Watch watches for events happening or that have happened. Both input and output
  // are streams; the input stream is for creating and canceling watchers and the output
  // stream sends events. One watch RPC can watch on multiple key ranges, streaming events
  // for several watches at once. The entire event history can be watched starting from the
  // last compaction revision.
  rpc Watch(stream WatchRequest) returns (stream WatchResponse) {
  }
}
]]
