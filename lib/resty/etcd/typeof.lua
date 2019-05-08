local INFINITE_POS = math.huge
local INFINITE_NEG = -INFINITE_POS
local type = type
local floor = math.floor
local rawequal = rawequal

local function typeof(cmp, arg)
    return cmp == type(arg)
end

local function typeof_nil(...)
    return typeof('nil', ...)
end

local function typeof_bool(...)
    return typeof('boolean', ...)
end

local function typeof_str(...)
    return typeof('string', ...)
end

local function typeof_num(...)
    return typeof('number', ...)
end

local function typeof_fun(...)
    return typeof('function', ...)
end

local function typeof_table(...)
    return typeof('table', ...)
end

local function typeof_thread(...)
    return typeof('thread', ...)
end

local function typeof_userdata(...)
    return typeof('userdata', ...)
end

local function typeof_finite(arg)
    return type(arg) == 'number' and (arg < INFINITE_POS and arg > INFINITE_NEG)
end

local function typeof_unsigned(arg)
    return type(arg) == 'number' and (arg < INFINITE_POS and arg >= 0)
end

local function typeof_int(arg)
    return typeof_finite(arg) and rawequal(floor(arg), arg)
end

local function typeof_int8(arg)
    return typeof_int(arg) and arg >= -128 and arg <= 127
end

local function typeof_int16(arg)
    return typeof_int(arg) and arg >= -32768 and arg <= 32767
end

local function typeof_int32(arg)
    return typeof_int(arg) and arg >= -2147483648 and arg <= 2147483647
end

local function typeof_uint(arg)
    return typeof_unsigned(arg) and rawequal(floor(arg), arg)
end

local function typeof_uint8(arg)
    return typeof_uint(arg) and arg <= 255
end

local function typeof_uint16(arg)
    return typeof_uint(arg) and arg <= 65535
end

local function typeof_uint32(arg)
    return typeof_uint(arg) and arg <= 4294967295
end

local function typeof_nan(arg)
    return arg ~= arg
end

local function typeof_non(arg)
    return arg == nil or arg == false or arg == 0 or arg == '' or arg ~= arg
end


local _M = {
    version = 0.1,
    ['nil'] = typeof_nil,
    ['boolean'] = typeof_bool,
    ['string'] = typeof_str,
    ['number'] = typeof_num,
    ['function'] = typeof_fun,
    ['table'] = typeof_table,
    ['thread'] = typeof_thread,
    ['userdata'] = typeof_userdata,
    ['finite'] = typeof_finite,
    ['unsigned'] = typeof_unsigned,
    ['int'] = typeof_int,
    ['int8'] = typeof_int8,
    ['int16'] = typeof_int16,
    ['int32'] = typeof_int32,
    ['uint'] = typeof_uint,
    ['uint8'] = typeof_uint8,
    ['uint16'] = typeof_uint16,
    ['uint32'] = typeof_uint32,
    ['nan'] = typeof_nan,
    ['non'] = typeof_non,
    -- alias
    ['Nil'] = typeof_nil,
    ['Function'] = typeof_fun
}

return _M
