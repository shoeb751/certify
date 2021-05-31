local c = require("config")
local lib = require("lib")
local log = require "certify.log"

local data = lib.get_body()
local certs,keys,csrs = lib.extract(data)

-- TODO: Do not delegate everything to lib module
--       Understandable higher level busineess logic should be
--       coded in this file.