#!/bin/bash
curl -k -X "PUT" "${AUTH_ENDPOINT_V2}/v2/auth/users/root" -H "Content-Type: application/json; charset=utf-8" -d $"{\"user\":\"${AUTH_USER}\",\"password\":\"${AUTH_PWD}\"}"
curl -k -X "PUT" "${AUTH_ENDPOINT_V2}/v2/auth/enable"
curl -k -X "PUT" "${AUTH_ENDPOINT_V2}/v2/auth/roles/guest" -H "Content-Type: text/plain; charset=utf-8" -u "${AUTH_USER}:${AUTH_PWD}" -d $'{"role":"guest","revoke":{"kv":{"write": ["/*"]}}}'
