local c = require("config")
local lib = require("lib")

local data = lib.get_body()
local certs,keys,csrs = lib.extract(data)