## Version Publish

After [#117](https://github.com/api7/lua-resty-etcd/pull/117) got merged, we could publish new version of lua-resty-etcd easily. All you need to do is:

- Create a PR that add the rockspec for the new version.
- Create a tag with format like 'v1.0'.

The tag would trigger Github Actions to upload to both luarocks and github release.
