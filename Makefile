PREFIX ?=          /usr/local/openresty
LUA_LIB_DIR ?=     $(PREFIX)/lualib/$(LUA_VERSION)
INSTALL ?= install

### install:      Install the library to runtime
.PHONY: install
install:
	$(INSTALL) lib/resty/*.lua $(LUA_LIB_DIR)/resty/

### dev:          Create a development ENV
.PHONY: dev
dev:
	luarocks install rockspec/lua-resty-etcd-master-0.1-0.rockspec --only-deps

### help:         Show Makefile rules
.PHONY: help
help:
	@echo Makefile rules:
	@echo
	@grep -E '^### [-A-Za-z0-9_]+:' Makefile | sed 's/###/   /'

### lint:             Lint Lua source code
.PHONY: lint
lint: utils
	./utils/check-lua-code-style.sh

### utils:            Installation tools
.PHONY: utils
utils:
ifeq ("$(wildcard utils/lj-releng)", "")
	wget -O utils/lj-releng https://raw.githubusercontent.com/iresty/openresty-devel-utils/master/lj-releng
	chmod a+x utils/lj-releng
endif

test:
	prove -I../test-nginx/lib -r -s t/
