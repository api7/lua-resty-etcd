# Etcd Cluster Health Check

## Description

Implement a passive health check mechanism, that when the connection/read/write fails, record it as an endpoint's failure.

## Methods

* [init](#init)
* [report_failure](#report_failure)
* [get_target_status](#get_target_status)

###  init

`syntax: health_check, err = health_check.init(params)`

Initializes the health check object, overiding default params with the given ones. In case of failures, returns `nil` and a string describing the error.

###  report_failure

`syntax: health_check.report_failure(etcd_host)`

Reports a health failure which will count against the number of occurrences required to make a target "fail".

###  get_target_status

`syntax: healthy, err = health_check.get_target_status(etcd_host)`

Get the current status of the target.

## Config

| name         | Type    | Requirement | Default | Description                                                  |
| ------------ | ------- | ----------- | ------- | ------------------------------------------------------------ |
| shm_name     | string  | required    |         | the declarative `lua_shared_dict` is used to store the health status of endpoints. |
| fail_timeout | integer | optional    | 10s     | sets the time during which the specified number of unsuccessful attempts to communicate with the endpoint should happen to marker the endpoint unavailable, and also sets the period of time the endpoint will be marked unavailable. |
| max_fails    | integer | optional    | 1       | sets the number of failed attempts that must occur during the `fail_timeout` period for the endpoint to be marked unavailable. |
| retry        | bool    | optional    | false   | automatically retry another endpoint when operations failed. |

lua example:

```lua
local health_check, err = require("resty.etcd.health_check").init({
    shm_name = "healthcheck_shm",
    fail_timeout = 10,
    max_fails = 1,
    retry = false,
})
```

In a `fail_timeout`, if there are `max_fails` consecutive failures, the endpoint is marked as unhealthy,  the unhealthy endpoint will not be choosed to connect for a `fail_timeout` time in the future.

Health check mechanism would switch endpoint only when the previously choosed endpoint is marked as unhealthy.

The failure counter and health status of each etcd endpoint are shared across workers and by different etcd clients.

Also note that the `fail_timeout`, `max_fails` and `retry` of the health check cannot be changed once it has been created.

##  Synopsis

```nginx
http {
    # required declares a shared memory zone to store endpoints's health status
    lua_shared_dict healthcheck_shm 1m;

    server {
        location = /healthcheck {
            content_by_lua_block {
                # the health check feature is optional, and can be enabled with the following configuration.
                local health_check, err = require("resty.etcd.health_check").init({
                    shm_name = "healthcheck_shm",
                    fail_timeout = 10,
                    max_fails = 1,
                    retry = false,
                })

                local etcd, err = require("resty.etcd").new({
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
