#! /usr/bin/env luajit
local l = require("lib")

local type = ngx.var.arg_type or "cert"
local db = l.db()
local query = ""
if type == "cert" then
  query = "SELECT id, name, fingerprint, expires FROM ssl_certs;"
elseif type == "key" then
  query = "SELECT id, name, modulus_sha1 FROM ssl_keys;"
else
  l.message_e("ERROR","Unknown type: " .. type)
end
local res, err, errcode, sqlstate = db:query(query)
if not res then
ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
return
end
ngx.header['Content-Type']= 'application/json'
local cjson = require("cjson")
ngx.say(cjson.encode(res))