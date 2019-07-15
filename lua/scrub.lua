#! /usr/bin/env luajit

local lib = require("lib")
local c = require("config")

-- creating objects that will be required later
local db = lib.db()
-- first get all certs that have not been validated
-- then make sure that the certs that have not been
-- validated are tried to be validated again

-- check if the required tables are present
-- if not present, create those tables

local ok,err = lib.check_db_setup(db)
if not ok then
    lib.message_e("ERROR", err)
end

local certs = lib.get_certs_to_be_validated(db)

for i,v in pairs(certs) do
    -- need to only get the ids in the output
    -- as that is what create_cert_chain expects
    local id = v["id"]
    _ , chain_exists = lib.create_cert_chain(id,db)
    if chain_exists then
        lib.update_cert_status_in_db(id,true,db)
    end
end

-- now get duplicates and archive those certs
local certs = lib.get_duplicate_certs(db)

-- We now need to find what certs are to be archived
local certs_to_delete = lib.process_duplicate(certs)

-- delete the certs one by one
for i,v in ipairs(certs_to_delete) do
    lib.archive('cert',v,db)
end

--now clean up keys that have no mappings
local keys = lib.get_unused_keys(db)
lib.d(keys)
-- keys is expected to be a list of ids
for i,v in ipairs(keys) do
    lib.archive('key',v["id"],db)
end
-- If everything goes well, all cleanup is complete