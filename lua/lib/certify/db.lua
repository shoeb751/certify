local log = require "certify.log"
local debug = require "certify.debug"

-- returns a DB object to be used to connect to mysql backend
-- Designed such that using a different DB should not be a problem
-- With a bit of time
local function get_connection()
    local mysql = require("mysql")
    local db, err = mysql:new()
    if not db then
        local cjson = require "cjson"
        return nil, cjson.encode({err=err})
    end

    -- perhaps db timeout can be exposed as a config
    db:set_timeout(1000) -- 1 sec
    local c = require "config"
    local ok, err, errcode, sqlstate = db:connect(c.mysql.auth)
    if not ok then
        local cjson = require "cjson"
        return nil, cjson.encode({err=err,errcode=errcode,sqlstate=sqlstate})
    else
        return db
    end
end

-- return result of query or error string
local function query(dbconn,query)
    local res, err, errcode, sqlstate = dbconn:query(query)
    if not res then
        local cjson = require "cjson"
        return nil, cjson.encode({err=err,errcode=errcode,sqlstate=sqlstate})
    else
        return res
    end
end



local db = {}
db.get_connection = get_connection
db.query = query
return db
