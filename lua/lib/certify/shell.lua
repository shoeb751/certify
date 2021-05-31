local log = require "certify.log"
local debug = require "certify.debug"
local c = require "config"

local shell_args = c.shell.args
local s = require "shell"

local shell = {}


local function run(cmd)
    local status, out, err = _M.shell.execute(cmd, shell_args)
    if not err then
        return out
    else
        return nil,err
    end
end

shell.run=run

return shell