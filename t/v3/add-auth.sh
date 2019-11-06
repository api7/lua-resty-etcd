#!/bin/bash
etcdctl --endpoints="${AUTH_ENDPOINT_V3}" role add root
etcdctl --endpoints="${AUTH_ENDPOINT_V3}" user add "${AUTH_USER}:${AUTH_PWD}"
etcdctl --endpoints="${AUTH_ENDPOINT_V3}" grant-role root
etcdctl --user="${AUTH_USER}:${AUTH_PWD}" --endpoints="${AUTH_ENDPOINT_V3}" auth enable