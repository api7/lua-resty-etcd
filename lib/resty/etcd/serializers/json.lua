local cjson = require("cjson.safe")


return {
    serialize   = cjson.encode,
    deserialize = cjson.decode
}
