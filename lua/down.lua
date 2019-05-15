#! /usr/bin/env luajit

local lib = require("lib")
local c = require("config")

local type = ngx.var.arg_type or "cert"
local dn = ngx.var.arg_dn
local id = ngx.var.arg_id or dn and lib.get_id_from_name(dn)
if not id then lib.message_e("ERROR","Requested Cert does not exist") end
local db = lib.db()
local out = {}

if type == "chain" then
  local chain = lib.create_cert_chain(id,db)
  out.name = chain[1]["name"]:gsub('*','star'):gsub(' ','_')
  local data = ""
  for i, v in ipairs(chain) do
    -- this is inefficient if chains are very long as this will require a lot of GC to create new
    -- strings and delete old versions as strings in lua are immutable
    data = data .. v.raw .. "\n"
  end
  out.data = data
elseif type == "ic" then
  local chain = lib.create_cert_chain(id,db)
  out.name = chain[1]["name"]:gsub('*','star'):gsub(' ','_')
  local data = ""
  for i, v in ipairs(chain) do
    if i ~= 1 then
    -- this is inefficient if chains are very long as this will require a lot of GC to create new
    -- strings and delete old versions as strings in lua are immutable
      data = data .. v.raw .. "\n"
    end
  end
  out.data = data
elseif type == "key" then
  local query = "SELECT  c.name as name, k.raw as raw \
                  from ssl_certs c \
                INNER JOIN ssl_keys k \
                ON c.modulus_sha1 = k.modulus_sha1 \
                WHERE c.id = ".. id ..";"
  local res, err, errcode, sqlstate = db:query(query)
  if not res then
  ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
  return
  end
  if #res == 0 then
    lib.message_e("ERROR","Resource not found with id: " .. id)
  end
  out.name = res[1]["name"]:gsub('*','star'):gsub(' ','_')
  out.data = res[1]["raw"]
else
  local query = "SELECT name as name, raw FROM " .. c.mysql.table[type] .. " where id = " .. id .. ";"
  local res, err, errcode, sqlstate = db:query(query)
  if not res then
  ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
  return
  end
  if #res == 0 then
    lib.message_e("ERROR","Resource not found with id: " .. id)
  end
  out.name = res[1]["name"]:gsub('*','star'):gsub(' ','_')
  out.data = res[1]["raw"]
end

-- spit out collected results
if type == "cert" then
  ngx.header['Content-Type'] = 'application/x-x509-ca-cert'
  ngx.header['Content-Disposition'] = 'attachment; filename="' .. out.name .. '.crt"'
elseif type == "key" then
  ngx.header['Content-Type'] = 'application/pkcs8'
  ngx.header['Content-Disposition'] = 'attachment; filename="' .. out.name .. '.key"'
elseif type == "chain" then
  ngx.header['Content-Type'] = 'application/x-x509-ca-cert'
  ngx.header['Content-Disposition'] = 'attachment; filename="' .. out.name .. '_chain.crt"'
elseif type == "ic" then
  ngx.header['Content-Type'] = 'application/x-x509-ca-cert'
  ngx.header['Content-Disposition'] = 'attachment; filename="' .. out.name .. '_ic_chain.crt"'
end
ngx.print(out.data)