local c = require("config")

local _M = {}

-- Adding Debug functionality
_M.debug = {}

_M.debug.dump_vars = function (var)
    if type(var) == "string" or type(var) == "number" then
        ngx.say(var)
    elseif type(var) == "table" then
        for key,value in pairs(var) do
            ngx.say(_M.debug.dump_vars(key))
            ngx.say(":")
            ngx.say(_M.debug.dump_vars(value))
        end
    elseif type(var) == "nil"  then
        ngx.say(var)
    else
        ngx.say(type(var) .. "Not being used for debug")
    end
end

local d = _M.debug.dump_vars
_M.d = d
_M.de = function (arg)
    d(arg)
    ngx.exit(200)
end

local de = _M.de

-- print  message and exit
_M.message_e = function (level, message)
    local level = level or "INFO"
    local message = message or "No message supplied"
    ngx.say(level .. ": " .. message)
    ngx.exit(200)
end
-- End debug funtionality

-- Setup common libs that can be used at multiple places:
-- Need to decide if these things can be moved to init_by_lua

_M.shell = require("shell")

_M.db = function ()
    local mysql = require("mysql")
    local db, err = mysql:new()
    if not db then
        ngx.say("failed to instantiate mysql: ", err)
        return
    end

    db:set_timeout(1000) -- 1 sec
    local ok, err, errcode, sqlstate = db:connect (c.mysql.auth)
    if not ok then
        de({ok,err,errcode,sqlstate})
        local error_message = "failed to connect: " .. err .. ": " .. errcode .. " " .. sqlstate
        de(error_message)
        return nil, error_message
    else
        return db
    end
end
-- End setup of common libs


_M.get_body = function ()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if body == nil or body == "" then
        _M.message_e("WARN","Request Body Empty :(")
    end
    return body
end

_M.check_for_multi = function (message)
    return select(2, message:gsub("BEGIN", ""))
end
-- extract certs, keys, csrs from text
_M.extract = function (message)
    local multi = _M.check_for_multi(message)
    local fil = _M.file_from_data (message)

    -- if multi cert, there will be more than 1 BEGIN
    if multi > 1 then
        _M.process_multi(fil)
    end

    local cmd = "file -b -m /etc/nginx/lua/config/magic_privatekey -m /usr/share/misc/magic " .. fil
    local out, err = _M.run_shell(cmd)
    if not out then
        _M.message_e("ERROR","Invalid Key: " .. err)
    end

    if out:find("certificate") then
        local certs = {_M.get_cert_details(message,fil)}
        for i,v in ipairs(certs) do
            _M.add_to_db("cert",v)
        end
    elseif out:find("key") then
        local keys = {_M.get_key_details(message,fil)}
        for i, v in ipairs(keys) do
            _M.add_to_db("key",v)
        end
    elseif out:find("Zip") then
        -- Here we are not going to be adding to the DB
        -- Using the generic add_to_db function
        -- Instead, we will upload the cert using multiple
        -- Curl calls to myself from inside the docker
        --_M.message_e("ERROR", "Zip processing not implemented")
        _M.process_zip(fil)
    else
        _M.message_e("ERROR", "No Cert or key found")
    end
end

_M.process_zip = function (f_name)
    local cmd = [[
        tmp_dir=$(mktemp -d); \
        unzip -q -d $tmp_dir %s && \
        find $tmp_dir -type f | \
        xargs -i sh -c "curl -s http://127.0.0.1/api/up --data-binary @{}" && \
        rm -rf $tmp_dir
    ]]
    cmd = string.format(cmd,f_name)
    local out, err = _M.run_shell(cmd)
    if not out then
        _M.message_e("ERROR","Could not process zip: " .. err)
    end
    _M.message_e("INFO",out)
end

_M.process_multi = function (f_name)
    local cmd = [[
        tmp_dir=$(mktemp -d); \
        cp {FNAME} $tmp_dir && \
        cd $tmp_dir && \
        awk ' \
        BEGIN{ n=0; cert=0; key=0; \
              if ( ARGC < 2 ) { print "Use a proper file name"; exit 1 } \
            } \
        /-----BEGIN PRIVATE KEY-----/      { key=1; cert=0 } \
        /-----BEGIN RSA PRIVATE KEY-----/  { key=1; cert=0 } \
        /-----BEGIN CERTIFICATE-----/      { cert=1; key=0 } \
        split_after == 1                   { n++; split_after=0 } \
        /-----END CERTIFICATE-----/        { split_after=1 } \
        /-----END PRIVATE KEY-----/        { split_after=1 } \
        /-----END RSA PRIVATE KEY-----/    { split_after=1 } \
        key == 1                       { print > FILENAME "-" n ".key" } \
        cert == 1                      { print > FILENAME "-" n ".crt" }' $(basename {FNAME}) && \
        rm {FNAME} $(basename {FNAME}) && \
        find $tmp_dir -type f | \
        xargs -i sh -c "curl -s http://127.0.0.1/api/up --data-binary @{}" && \
        rm -r $tmp_dir
    ]]
    cmd = cmd:gsub("{FNAME}",f_name)
    local out, err = _M.run_shell(cmd)
    if not out then
        _M.message_e("ERROR","Could not process multicert: " .. err)
    end
    _M.message_e("INFO",out)
end

_M.run_shell = function (cmd)
    local status, out, err = _M.shell.execute(cmd, c.shell.args)
    if not err then
        return out
    else
        return nil,err
    end
end

_M.sanitize = function (obj)
    n_obj = {}
    if type(obj) == "string" then
        return obj:gsub("%s+$",""):gsub("^%s+",""):gsub("'","''")
    end
    for k,v in pairs(obj) do
        n_obj[k] = v:gsub("%s+$",""):gsub("^%s+",""):gsub("'","''")
    end
    return n_obj
end


_M.get_key_details = function (data,fil)
    local key = {}
    key.raw = data
    local cmd = "openssl rsa -check -in " .. fil .. " -noout -text | grep -E 'Private|RSA'"
    local out, err = _M.run_shell(cmd)
    if not out then
        _M.message_e("ERROR","Invalid Key: " .. err)
    end
    local k = out
    if not k:find("RSA key ok") then
        _M.message_e("ERROR","invalid key or format: " .. k)
    else
        ngx.say("key OK")
    end
    local cmd = "openssl rsa -in " .. fil .. " 2>/dev/null"
    local out, err = _M.run_shell(cmd)
    if not out then
        _M.message_e("ERROR","Invalid Key: " .. err)
    else
        key.raw = out
    end
    local cmd = "openssl rsa -noout -modulus -in " .. fil .. " | cut -d= -f 2 | sha1sum | cut -d' ' -f 1"
    local status, out, err = _M.shell.execute(cmd, c.shell.args)
    key.modulus_sha1 = out
    local cmd = 'date -u +"%Y-%m-%d %H:%M:%S"'
    local status, out, err = _M.shell.execute(cmd, c.shell.args)
    key.now = out
    return _M.sanitize(key)
end

_M.get_cert_details = function (crt, fil)
    local cert = {}
    cert.raw = crt
    local cmd = "openssl x509 -noout -subject -issuer -fingerprint -enddate -in " .. fil
    local out, err = _M.run_shell(cmd)
    if not out then
        _M.message_e("ERROR","Invalid Certificate: " .. err)
    else
        cert.out = out
    end
    local k = cert.out
    local subject = k:match("subject=%s-(.-)\n")
    cert.subject = subject
    cert.name = subject:match("CN=%s-(.-)$")
    cert.issuer = k:match("issuer=%s-(.-)\n")
    cert.fingerprint = k:match("SHA1 Fingerprint=%s-(.-)\n")
    local expiry = k:match("notAfter=%s-(.-)\n")
    local cmd = "date -d \"".. expiry .. "\" -u +\"%Y-%m-%d %H:%M:%S\""
    local status, out, err = _M.shell.execute(cmd, c.shell.args)
    cert.expiry = out
    local cmd = 'date -u +"%Y-%m-%d %H:%M:%S"'
    local status, out, err = _M.shell.execute(cmd, c.shell.args)
    cert.now = out
    local cmd = "openssl x509 -noout -modulus -in " .. fil .. " | cut -d= -f 2 | sha1sum | cut -d' ' -f 1"
    local status, out, err = _M.shell.execute(cmd, c.shell.args)
    cert.modulus_sha1 = out
    cert.out = nil
    return _M.sanitize(cert)
end

_M.file_from_data = function (data)
    local fil = "/tmp/luatmp/" .. ngx.time() .. ".dat"
    local f,err = io.open(fil,"w")
    f:write(data)
    if not f then
        ngx.say(err)
    else
        f:close()
        ngx.say("Done uploading file")
    end
    return fil
end

_M.db_query = function (db_instance, query)
    local res, err, errcode, sqlstate = db_instance:query(query)
    if not res then
        ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
        return
    end
    return res
end

_M.get_id_from_name = function (name,exit)
    -- this is one or two additional DB calls
    -- so that I do not have to refactor functions
    -- to account for the name
    local db, err = _M.db()
    if not db then de(err) end
    local type = "cert"
    local query = "SELECT id, name FROM " .. c.mysql.table[type] .. " where name = '" .. name .. "' ORDER BY expires DESC LIMIT 1;"
    local res = _M.db_query(db,query)
    -- exit means it is tying wildcard match
    if exit then return res[1] and res[1]["id"] end
    -- if no results for specific match, try wildcard match
    if #res == 0 then
        return _M.get_id_from_name("*." .. name:gsub('^%w+%.',''),true)
    else
        return res[1] and res[1]["id"]
    end
end

_M.add_to_db = function (type,obj)
    -- its job is to check if things are already in the DB
    -- if not , add, if there, return with error
    -- returns out, nil or nil, err
    local db, err = _M.db()
    if not db then de(err) end
    if not c.mysql.table[type] then
        de("Wrong type passed to add_to_db")
    end
    local query = ""
    if type == 'cert' then
        query = "SELECT COUNT(*) AS count from " .. c.mysql.table[type] .. " WHERE fingerprint = '".. obj.fingerprint .."';"
    elseif type == 'key' then
        query = "SELECT COUNT(*) AS count from " .. c.mysql.table[type] .. " WHERE modulus_sha1 = '".. obj.modulus_sha1 .."';"
    end
    local res, err, errcode, sqlstate = db:query(query)
    if not res then
        ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
        return
    end
    if tonumber(res[1]["count"]) ~= 0 then
        ngx.say (type .. " already exists")
    else
        if not obj.name then
            obj.name = "NA"
        end
        local query = ""
        if type == 'cert' then
            -- creation of query can be offloaded to a new function
            -- where we can also make the tables dynamic rather than
            -- being hardcoded as they are right now
            query = [[
                INSERT INTO ssl_certs (
                    name,
                    last_change,
                    subject,
                    issuer,
                    fingerprint,
                    raw,
                    modulus_sha1,
                    expires ) ]] .. "VALUES ('"
                    .. obj.name .. "','"
                    .. obj.now .. "','"
                    .. obj.subject .. "','"
                    .. obj.issuer .. "','"
                    .. obj.fingerprint .. "','"
                    .. obj.raw .. "','"
                    .. obj.modulus_sha1 .. "','"
                    .. obj.expiry .. "');"
        elseif type == 'key' then
            query = [[
                INSERT INTO ssl_keys (
                    name,
                    last_change,
                    raw,
                    modulus_sha1 )]] .. "VALUES ( '"
                    .. obj.name .. "','"
                    .. obj.now .. "','"
                    .. obj.raw .. "','"
                    .. obj.modulus_sha1 .. "');"
        end
        local res, err, errcode, sqlstate = db:query(query)
        if not res then
            ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
            return
        end
        ngx.say(type .. " added to library")
    end

end

_M.create_cert_chain = function (id,db,chain)
    -- Chain will contain the number of entries
    if not chain then
        local chain = {}
        query = "SELECT name, issuer, raw from ssl_certs WHERE id = " .. id ..";"
        local res, err, errcode, sqlstate = db:query(query)
        if not res then
        ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
        return
        end
        if #res == 0 then
            return chain
        else
            table.insert(chain, res[1])
            return _M.create_cert_chain(id,db,chain)
        end
    else
        subject = chain[#chain]["issuer"]
        sub_sanitized = subject:gsub("'","''")
        query = "SELECT issuer, raw FROM ssl_certs WHERE subject = '" .. sub_sanitized .. "' ORDER BY expires DESC LIMIT 1;"
        local res, err, errcode, sqlstate = db:query(query)
        if not res then
        ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
        return
        end
        if #res == 0 or #chain > 10 then
            return chain
        elseif res[1]["issuer"] == subject then
            table.insert(chain,res[1])
            return chain
        else
            table.insert(chain,res[1])
            return _M.create_cert_chain(id,db,chain)
        end
    end
end

return _M