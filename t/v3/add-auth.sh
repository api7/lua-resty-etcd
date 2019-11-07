#!/bin/bash
export ETCDCTL_API=3
etcdctl version 
etcdctl --endpoints="${AUTH_ENDPOINT_V3}" user add "${AUTH_USER}:${AUTH_PWD}"
etcdctl --endpoints="${AUTH_ENDPOINT_V3}" role add root
etcdctl --endpoints="${AUTH_ENDPOINT_V3}" user grant-role root root
etcdctl --endpoints="${AUTH_ENDPOINT_V3}" role list
etcdctl --endpoints="${AUTH_ENDPOINT_V3}" user list
etcdctl --endpoints="${AUTH_ENDPOINT_V3}" auth enable
