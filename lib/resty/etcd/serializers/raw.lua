local type = type


local function raw_encode(v)
    local t = type(v)
    if t ~= 'string' then
        return nil, 'unsupported type for ' .. t
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
