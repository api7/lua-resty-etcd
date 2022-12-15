#!/bin/bash
export ETCDCTL_API=3
etcdctl version
etcdctl ${ETCDCTL_EXTRA_OPTS} --endpoints="${AUTH_ENDPOINT_V3}" user add "${AUTH_USER}:${AUTH_PWD}"
etcdctl ${ETCDCTL_EXTRA_OPTS} --endpoints="${AUTH_ENDPOINT_V3}" role add root
etcdctl ${ETCDCTL_EXTRA_OPTS} --endpoints="${AUTH_ENDPOINT_V3}" user grant-role root root
etcdctl ${ETCDCTL_EXTRA_OPTS} --endpoints="${AUTH_ENDPOINT_V3}" role list
etcdctl ${ETCDCTL_EXTRA_OPTS} --endpoints="${AUTH_ENDPOINT_V3}" user list
etcdctl ${ETCDCTL_EXTRA_OPTS} --endpoints="${AUTH_ENDPOINT_V3}" auth enable
