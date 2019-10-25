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
	luarocks install rockspec/lua-resty-etcd-dev-0.1-0.rockspec --only-deps

### help:         Show Makefile rules
.PHONY: help
help:
	@echo Makefile rules:
	@echo
	@grep -E '^### [-A-Za-z0-9_]+:' Makefile | sed 's/###/   /'

test:
	prove -I../test-nginx/lib -r -s t/
