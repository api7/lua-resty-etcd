Etcd Cluster Health Check
========

Synopsis
========

```nginx
http {
    # required declares a shared memory zone to store endpoints's health status
    lua_shared_dict healthcheck_shm 1m;

    server {
        location = /healthcheck {
            content_by_lua_block {
                local etcd, err = require "resty.etcd" .new({
                    protocol = "v3",
                    http_host = {
                        "http://127.0.0.1:12379", 
                        "http://127.0.0.1:22379",
                        "http://127.0.0.1:32379",
                    },
                    user = 'root',
                    password = 'abc123',
                    # minimal configuration to enable etcd cluster health check
                    cluster_healthcheck ={
                        shm_name = 'healthcheck_shm',
                    }
                })
            }
        }
    }
}
```

Description
========

Implement a passive health check mechanism, when the connection/read/write fails occurs, recorded as a endpoint' failure.

In a `failure_window`, if there are `failure_times` consecutive failures, the endpoint is marked as unhealthy,  the unhealthy endpoint will not be choosed to connect for a `disable_duration` time in the future. 

Health check mechanism would switch endpoint only when the previously choosed endpoint is marked as unhealthy.

Config
========

The default configuration is as follows:

```lua
health_check = {
    shm_name = "healthcheck_shm",
    failure_window = 1,
    failure_times = 1,
    disable_duration = 100
}
```

when use `require "resty.etcd" .new` to create a connection, you can override the default configuration like

```lua
    local etcd, err = require "resty.etcd" .new({
        protocol = "v3",
        http_host = {
            "http://127.0.0.1:12379",
            "http://127.0.0.1:22379",
            "http://127.0.0.1:32379",
        },
        user = 'root',
        password = 'abc123',
        health_check = {
            shm_name = "etcd_cluster_health_check",
            failure_window = 3,
            failure_times = 2,
            disable_duration = 10,
        },
    })
```

configurations that are not overridden will use the default configuration.

- `shm_name` : the declarative `lua_shared_dict` is used to store the health status of endpoints.
- `failure_window` : the duration of endpoint occurs n consecutive failures(in seconds).
- `failure_times` : the times of failures that occurred before the endpoint was marked as unhealthy.
- `disable_duration` : the duration of the unhealthy endpoint will not be choosed to connect(in seconds).

### tips
- enable the cluster health check by config the `health_check`
