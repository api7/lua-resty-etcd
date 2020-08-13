local function raw_encode(v)
    if v and type(v) ~= 'string' then
        return nil, "unsupported type for " .. type(v)
    end
    return v
end

local function raw_decode(v)
    return v
end

return {
    serialize   = raw_encode,
    deserialize = raw_decode
}
