-- response lib
-- All user facing responses are supposed to use this library
-- Instead of directly calling ngx.say
--[[
    Functions expected:
    1) Part response (Equivalent to ngx.say)
    2) Response and exit with status (equivalent to lib.message_e)
]]
local log = require "certify.log"
local debug = require "certify.debug"

local res = {}

-- function to be modified in future according to requirements
local function send(data)
    table.insert(ngx.ctx.res, data)
end

local function setstatus(status)
    if ngx.ctx.status ~= status then
        log.debug("StatusChange",ngx.ctx.status,status)
    end
    ngx.ctx.status = status
end

local function exit(status,message)
    setstatus(status)
    send(message)
    ngx.exit(0)
end

res.send = send
res.setstatus = setstatus
res.exit=exit

return res
