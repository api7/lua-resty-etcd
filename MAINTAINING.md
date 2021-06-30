## Version Publish

After [#137](https://github.com/api7/lua-resty-etcd/pull/137) got merged, we could publish new version of lua-resty-etcd easily. All you need to do is:

- Create the release PR following the format `feat: release VERSION`, where `VERSION` should be the version used in the rockspec name, like `1.0` for `lua-resty-etcd-1.0-0.rockspec`.

When the PR got merged, it would trigger Github Actions to upload to both github release and luarocks.
