#!/bin/sh

set -ex

luacheck -q lib

find lib -name '*.lua' -exec ./utils/lj-releng {} + > \
    /tmp/check.log 2>&1 || (cat /tmp/check.log && exit 1)

grep -E "ERROR.*.lua:" /tmp/check.log > /tmp/error.log | true
if [ -s /tmp/error.log ]; then
    echo "=====bad style====="
    cat /tmp/check.log
    exit 1
fi
