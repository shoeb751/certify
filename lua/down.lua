#! /usr/bin/env luajit

local lib = require("lib")
local c = require("config")

local log = require "certify.log"
local debug = require "certify.debug"
local response = require "certify.res"
local dblib = require "certify.db"

-- default type is cert, so set that if not specified
local type = ngx.var.arg_type or "cert"
log.debug("Down","type",type)
-- dn is the domain for which we are asking for cert
-- Either dn or id is required to uniquely identify certs
local dn = ngx.var.arg_dn
log.debug("Down","dn",dn)
-- id of the cert, get from arg or generate from dn if dn is present
local id = ngx.var.arg_id or dn and lib.get_id_from_name(dn)
log.debug("Down","id",id)
-- if id is not present, we cannot proceed further
if not id then
    response.exit(400, "ID could not be found, check dn or specify id")
end

local db, err = dblib.get_connection()
if not db then
    log.warn("DownDBConnect", err)
    response.exit(500, err)
end

local out = {}

-- right now, we generate the chain on demand. This can be cached if required in
-- future
if type == "chain" then
    local chain = lib.create_cert_chain(id, db)
    -- making sure that cert name does not have spaces or *
    out.name = chain[1]["name"]:gsub('*', 'star'):gsub(' ', '_')
    local data = ""
    for i, v in ipairs(chain) do
        -- this is inefficient if chains are very long as this will require a lot of
        -- GC to create new strings and delete old versions as strings in lua are
        -- immutable
        data = data .. v.raw .. "\n"
    end
    out.data = data
elseif type == "ic" then
    local chain = lib.create_cert_chain(id, db)
    out.name = chain[1]["name"]:gsub('*', 'star'):gsub(' ', '_')
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
                  from " .. c.mysql.table["cert"] .. " c \
                INNER JOIN " .. c.mysql.table["key"] .. " k \
                ON c.modulus_sha1 = k.modulus_sha1 \
                WHERE c.id = " .. id .. ";"
    log.trace("Down","Key",query)
    local res, err = dblib.query(db, query)
    if not res then
        log.warn("DownDBKey", err)
        response.exit(500, err)
    end
    if #res == 0 then
        response.exit(404, "Key not found with id: " .. id)
    end
    out.name = res[1]["name"]:gsub('*', 'star'):gsub(' ', '_')
    out.data = res[1]["raw"]
elseif type == "fingerprint" then
    -- this is supposed to return the fingerprint for the domain
    -- note: only cert fingerprints exist
    local query = "SELECT name as name, fingerprint FROM " .. c.mysql.table["cert"] .. " where id = " .. id .. ";"
    local res, err = dblib.query(db, query)
    if not res then
        log.warn("DownDBFingerprint", err)
        response.exit(500, err)
    end
    if #res == 0 then
        response.exit(404, "Fingerprint not found with id: " .. id)
    end
    out.data = res[1]["fingerprint"]
else
    -- here we will only download the cert
    -- if you fall through to here, we are only downloading cert
    local query = "SELECT name as name, raw FROM " .. c.mysql.table["cert"] .. " where id = " .. id .. ";"
    local res, err = dblib.query(db, query)
    if not res then
        log.warn("DownDBCert", err)
        response.exit(500, err)
    end
    if #res == 0 then
        response.exit(404, "Cert not found with id: " .. id)
    end
    out.name = res[1]["name"]:gsub('*', 'star'):gsub(' ', '_')
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
response.send(out.data)

-- TODO: Seperate the various calls into a generic process that would
--       1) Generate the query
--       2) Do Post Processing based on requirements
--       This will allow in future to add other types of cert downloads
--       without adding to the mess of if else statements here.
--       2 lib functions still in use in this file which either need moving, or replacing