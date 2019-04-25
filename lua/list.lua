#! /usr/bin/env luajit
local l = require("lib")

local db = l.db()
local query = [[
  SELECT  c.id, c.name, c.fingerprint, c.expires, NOT ISNULL(k.raw) as key_exists
  FROM ssl_certs c
  LEFT JOIN ssl_keys k
  ON c.modulus_sha1 = k.modulus_sha1
  ORDER BY id;
  ]]
local res, err, errcode, sqlstate = db:query(query)
if not res then
ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
return
end
ngx.header['Content-Type']= 'application/json'
local cjson = require("cjson")
ngx.say(cjson.encode(res))