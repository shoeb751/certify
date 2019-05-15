#! /usr/bin/env luajit
local l = require("lib")

local db = l.db()
local query = [[
  SELECT  c.id, c.name, c.fingerprint, {ISSUER} c.expires, NOT ISNULL(k.raw) as key_exists
  FROM ssl_certs c
  {JTYPE} JOIN ssl_keys k
  ON c.modulus_sha1 = k.modulus_sha1
  ORDER BY id;
  ]]
if ngx.var.arg_all then
  query = query:gsub("{JTYPE}","LEFT")
else
  query = query:gsub("{JTYPE}","INNER")
end

if ngx.var.arg_issuer then
  query = query:gsub("{ISSUER}","c.issuer,")
else
  query = query:gsub("{ISSUER}","")
end
local res, err, errcode, sqlstate = db:query(query)
if not res then
ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
return
end
ngx.header['Content-Type']= 'application/json'
local cjson = require("cjson")
ngx.say(cjson.encode(res))