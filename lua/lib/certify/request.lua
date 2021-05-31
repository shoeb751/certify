local log = require "certify.log"
local debug = require "certify.debug"

-- functions related to getting data from request

local request = {}

local function get_body()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if body == nil then
        local tmp_file = ngx.req.get_body_file()
        local f = assert(io.open(tmp_file, "rb"))
        body = f:read("*all")
        f:close()
    end
    -- this is required so that the calling function 
    -- will treat empty body as an error
    if body == nil or body == "" then
        local cjson = require "cjson"
        return nil, cjson.encode({err="Empty Request Body"})
    end
    return body
end

request.get_body=get_body

return request