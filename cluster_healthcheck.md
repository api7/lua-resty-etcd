Etcd Cluster Health Check
========

Status
========

This feature is still under early development.

Synopsis
========

```nginx
http {
    # required configuration for use the lua-resty-healthcheck-api7 library
    lua_shared_dict healthcheck_shm 1m;
    lua_shared_dict my_worker_events 1m;

    init_worker_by_lua_block {
        local we = require "resty.worker.events"
        local ok, err = we.configure({
            shm = "my_worker_events",
            interval = 0.1
        })
        if not ok then
            ngx.log(ngx.ERR, "failed to configure worker events: ", err)
            return
        end
    }

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

This feature uses the [lua-resty-healthcheck-api7](https://github.com/api7/lua-resty-healthcheck) to support `healthcheck` when connect to etcd cluster.

When network partition or node unavailable occurs in an etcd cluster, automatically selects health node to operate on, and track unhealthy nodes until they are healthy again.

Please refer the `healthcheck` guide documentaion at - https://github.com/api7/lua-resty-healthcheck for more details.

Config
========

The default configuration is as follows:

```
{
    active = {
        concurrency = 5,
        timeout = 5,
        http_path = "/health",
        host = "",
        type = "http",
        req_headers = {"User-Agent: curl/7.29.0"},
        https_verify_certificate = false,
        healthy = {
            http_statuses = {200},
            --active healthy health checks are disabled by default
            interval = 0,
            successes = 1,
        },
        unhealthy = {
            http_statuses = {500, 501, 503, 502, 504, 505},
            interval = 1,
            http_failures = 1,
            tcp_failures = 1,
            timeouts = 1,
        },
    },
    passive = {
        type = "http",
        healthy = {
            http_statuses = {200, 201},
            successes = 1,
        },
        unhealthy = {
        
            http_statuses = {500},
            http_failures = 1,
            tcp_failures = 1,
            --passive health checks are disabled by default
            timeouts = 0,
        },
    },
}
```

when use `require "resty.etcd" .new` to create a connection, you can override the default configuration like

```
    local etcd, err = require "resty.etcd" .new({
        protocol = "v3",
        http_host = {
            "http://127.0.0.1:12379",
            "http://127.0.0.1:22379",
            "http://127.0.0.1:32379",
        },
        user = 'root',
        password = 'abc123',
        cluster_healthcheck = {
            shm_name = 'test_shm',
            checks = {
                active = {
                    http_path = "/health",
                    timeout = 1,
                    healthy = {
                        http_statuses = {200},
                        interval = 0.5,
                    },
                },
            },
        },
    })
```

configurations that are not overridden will use the default configuration.

### tips
- enable the cluster health check by config the `cluster_healthcheck`
- only enable `active.unhealthy` check by default

Support Version
========
This feature support the etcd server version >= 3.3.0