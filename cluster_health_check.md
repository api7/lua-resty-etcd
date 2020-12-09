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

                    # the health check feature is optional, and can be enabled with the following configuration.
                    health_check = {
                        shm_name = 'healthcheck_shm',
                        fail_timeout = 1,
                        max_fails = 1,
                        disable_duration = 100
                    }
                })
            }
        }
    }
}
```

Description
========

Implement a passive health check mechanism, when the connection/read/write fails occurs, recorded as an endpoint' failure.

In a `fail_timeout`, if there are `max_fails` consecutive failures, the endpoint is marked as unhealthy,  the unhealthy endpoint will not be choosed to connect for a `disable_duration` time in the future. 

Health check mechanism would switch endpoint only when the previously choosed endpoint is marked as unhealthy.

Config
========

The default configuration is as follows:

```lua
health_check = {
    shm_name = "healthcheck_shm",
    fail_timeout = 1,
    max_fails = 1,
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
            fail_timeout = 3,
            max_fails = 2,
            disable_duration = 10,
        },
    })
```

configurations that are not overridden will use the default configuration.

- `shm_name`: the declarative `lua_shared_dict` is used to store the health status of endpoints.
- `fail_timeout`: set the time during which a number of failed attempts must happen for the endpoint to be marked unavailable(in seconds).
- `max_fails`: set the number of failed attempts that must occur during the `fail_timeout` period for the endpoint to be marked unavailable
- `disable_duration`: the time for which the unhealthy endpoint won't be choosed to connect(in seconds).
