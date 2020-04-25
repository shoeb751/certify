#! /usr/bin/env luajit

local lib = require("lib")
local c = require("config")

-- default type is cert, so set that if not specified
local type = ngx.var.arg_type or "cert"

-- dn is the domain for which we are asking for cert
-- Either dn or id is required to uniquely identify certs
local dn = ngx.var.arg_dn

-- id of the cert, get from arg or generate from dn if dn is present
local id = ngx.var.arg_id or dn and lib.get_id_from_name(dn)

-- if id is not present, we cannot proceed further
if not id then lib.message_e("ERROR","Requested Cert does not exist") end

local db = lib.db()
local out = {}

-- right now, we generate the chain on demand. This can be cached if required in
-- future
if type == "chain" then
  local chain = lib.create_cert_chain(id,db)
  -- making sure that cert name does not have spaces or *
  out.name = chain[1]["name"]:gsub('*','star'):gsub(' ','_')
  local data = ""
  for i, v in ipairs(chain) do
    -- this is inefficient if chains are very long as this will require a lot of
    -- GC to create new strings and delete old versions as strings in lua are
    -- immutable
    data = data .. v.raw .. "\n"
  end
  out.data = data
elseif type == "ic" then
  local chain = lib.create_cert_chain(id,db)
  out.name = chain[1]["name"]:gsub('*','star'):gsub(' ','_')
  local data = ""
  for i, v in ipairs(chain) do
    -- here we skip the first cert as we are generating an intemediate cert
    if i ~= 1 then
    -- this is inefficient if chains are very long as this will require a lot of
    -- GC to create new strings and delete old versions as strings in lua are
    -- immutable
      data = data .. v.raw .. "\n"
    end
  end
  out.data = data
elseif type == "key" then
  local query = "SELECT  c.name as name, k.raw as raw \
                  from " .. c.mysql.table["cert"] .. "c \
                INNER JOIN " .. c.mysql.table["key"] .. " k \
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
elseif type == "fingerprint" then
  -- this is supposed to return the fingerprint for the domain
  -- note: only cert fingerprints exist
  local query = "SELECT name as name, fingerprint FROM " .. c.mysql.table["cert"] .. " where id = " .. id .. ";"
  local res, err, errcode, sqlstate = db:query(query)
  if not res then
    ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
    return
  end
  if #res == 0 then
    lib.message_e("ERROR","Resource not found with id: " .. id)
  end
  out.data = res[1]["fingerprint"]
else
  -- here we will only download the cert
  -- if you fall through to here, we are only downloading cert
  local query = "SELECT name as name, raw FROM " .. c.mysql.table["cert"] .. " where id = " .. id .. ";"
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
elseif type == "fingerprint" then
  ngx.header['Content-Type'] = 'text/plain'
end

-- give the actual data in the body of the response
ngx.print(out.data)