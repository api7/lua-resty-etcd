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
                # the health check feature is optional, and can be enabled with the following configuration.
                local health_check, err = require "resty.etcd.health_check".new({
                    shm_name = "healthcheck_shm",
                    fail_timeout = 10,
                    max_fails = 1,
                })

                local etcd, err = require "resty.etcd".new({
                    protocol = "v3",
                    http_host = {
                        "http://127.0.0.1:12379", 
                        "http://127.0.0.1:22379",
                        "http://127.0.0.1:32379",
                    },
                    user = 'root',
                    password = 'abc123',
                })
            }
        }
    }
}
```

Description
========

Implement a passive health check mechanism, when the connection/read/write fails occurs, recorded as an endpoint' failure.

In a `fail_timeout`, if there are `max_fails` consecutive failures, the endpoint is marked as unhealthy,  the unhealthy endpoint will not be choosed to connect for a `fail_timeout` time in the future. 

Health check mechanism would switch endpoint only when the previously choosed endpoint is marked as unhealthy.

The failure counter and health status of each etcd endpoint are shared across workers and by different etcd clients.

Config
========

The default configuration is as follows:

```lua
health_check = {
    shm_name = "healthcheck_shm",
    fail_timeout = 10,
    max_fails = 1,
}
```

- `shm_name`: the declarative `lua_shared_dict` is used to store the health status of endpoints.
- `fail_timeout`: sets the time during which a number of failed attempts must happen for the endpoint to be marked unavailable, and also the time for which the endpoint is marked unavailable(default is 10 seconds).
- `max_fails`: sets the number of failed attempts that must occur during the `fail_timeout` period for the endpoint to be marked unavailable (default is 1 attempt).

Also note that the `fail_timeout` and `max_fails` of the health check cannot be changed once it has been created.
