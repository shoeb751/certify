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

if ngx.var.arg_concise then
  -- Here id is required as we need to create download link
  -- even though we do not directly display id on interface
  query = [[
    SELECT  c.id, c.name as Domain,
        DATEDIFF(c.expires,CURDATE()) as 'Days',
        c.expires as 'Expires On',
        SUBSTRING_INDEX(c.issuer, '/', -1) as Issuer
    FROM ssl_certs c
    INNER JOIN ssl_keys k
        ON c.modulus_sha1 = k.modulus_sha1
        {NAME_COND}
        ORDER BY c.expires
  ]]
end
if ngx.var.arg_name and ngx.var.arg_name ~= "" then
  local name = ngx.var.arg_name
  local cond = "WHERE c.name LIKE '%%" .. name .. "%%'"
  query = query:gsub("{NAME_COND}",cond)
else
  query = query:gsub("{NAME_COND}", "")
end
local res, err, errcode, sqlstate = db:query(query)
if not res then
ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
return
end
ngx.header['Content-Type']= 'application/json'
local cjson = require("cjson")
ngx.say(cjson.encode(res))