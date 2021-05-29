-- provide debug funtions to print things
-- that are not easily possible
local log = require "certify.log"

local stype = {
    string = true,
    number = true,
    table = true,
    ["nil"] = true
}

local function dump(var)
    local vtype = type(var)
    if not stype[vtype] then
        log.debug("Type: " .. vtype .. " not supported for logging")
    else
        local cjson = require("cjson")
        log.debug(cjson.encode(var))
    end
end

local debug = {}
debug.dump = dump
return debug
