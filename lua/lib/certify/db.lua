local log = require "certify.log"
local debug = require "certify.debug"
local de = debug.de

local function get_connection()
    local mysql = require("mysql")
    local db, err = mysql:new()
    if not db then
        log.error("failed to instantiate mysql: ", err)
        return
    end

    db:set_timeout(1000) -- 1 sec
    local c = require "config"
    local ok, err, errcode, sqlstate = db:connect(c.mysql.auth)
    if not ok then
        de({ok, err, errcode, sqlstate})
        local error_message = "failed to connect: " .. err .. ": " .. errcode .. " " .. sqlstate
        de(error_message)
        return nil, error_message
    else
        return db
    end
end

local db = {}
db.get_connection = get_connection
return db
