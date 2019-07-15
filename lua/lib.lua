local c = require("config")

local _M = {}

-- Adding Debug functionality
_M.debug = {}

function _M.debug.dump_vars (var)
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
function _M.de (arg)
    d(arg)
    ngx.exit(200)
end

local de = _M.de

-- print  message and exit
function _M.message_e (level, message)
    local level = level or "INFO"
    if not message then
        message = debug.traceback()
    end
    local message = message or "No message supplied"
    ngx.say(level .. ": " .. message)
    ngx.exit(200)
end
-- End debug funtionality

-- Setup common libs that can be used at multiple places:
-- Need to decide if these things can be moved to init_by_lua

_M.shell = require("shell")

function _M.db ()
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


function _M.get_body ()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if body == nil then
        local tmp_file = ngx.req.get_body_file()
        local f = assert(io.open(tmp_file, "rb"))
        body = f:read("*all")
        f:close()
    end 
    if body == nil or body == "" then
        _M.message_e("WARN","Request Body Empty :(")
    end
    return body
end

function _M.check_for_multi (message)
    return select(2, message:gsub("BEGIN", ""))
end
-- extract certs, keys, csrs from text
function _M.extract (message)
    local multi = _M.check_for_multi(message)
    local fil = _M.file_from_data (message)

    -- if multi cert, there will be more than 1 BEGIN
    if multi > 1 then
        _M.d("multi detected")
        _M.process_multi(fil)
    end
    -- remove empty lines and then find type of file
    local cmd = "sed -i '/^$/d' " .. fil .. "&& file -b -m /etc/nginx/lua/config/magic_privatekey -m /usr/share/misc/magic " .. fil
    local out, err = _M.run_shell(cmd)
    if not out then
        _M.message_e("ERROR","Invalid Key: " .. err)
    end

    if out:find("certificate") then
        _M.d("cert detected")
        local certs = {_M.get_cert_details(message,fil)}
        for i,v in ipairs(certs) do
            _M.add_to_db("cert",v)
        end
    elseif out:find("key") then
        _M.d("key detected")
        local keys = {_M.get_key_details(message,fil)}
        for i, v in ipairs(keys) do
            _M.add_to_db("key",v)
        end
    elseif out:find("Zip") then
        _M.d("zip detected")
        -- Here we are not going to be adding to the DB
        -- Using the generic add_to_db function
        -- Instead, we will upload the cert using multiple
        -- Curl calls to myself from inside the docker
        --_M.message_e("ERROR", "Zip processing not implemented")
        _M.process_zip(fil)
    else
        _M.d("===")
        _M.d(message)
        _M.d("===")
        _M.message_e("ERROR", "No Cert or key found")
    end
end

function _M.process_zip (f_name)
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

function _M.process_multi (f_name)
    -- Three things are being done here
    -- 1) Split multi cert into a single one
    -- 2) Remove empty lines from file
    -- 3) Upload each cert individually
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
        xargs -i sh -c "sed -i '/^$/d' {}" && \
        find $tmp_dir -type f | \
        xargs -i sh -c "curl -s 'http://127.0.0.1/api/up{AUTH}' --data-binary @{}" && \
        rm -r $tmp_dir
    ]]

    -- Adding logic to pass the auth to multi cert requests
    local auth = ngx.var.arg_auth
    if auth then
        auth = "?&auth=" .. auth
    else
        auth = ""
    end
    cmd = cmd:gsub("{FNAME}",f_name):gsub("{AUTH}",auth)
    _M.d(cmd)
    local out, err = _M.run_shell(cmd)
    if not out then
        _M.message_e("ERROR","Could not process multicert: " .. err)
    end
    _M.message_e("INFO",out)
end

function _M.run_shell (cmd)
    local status, out, err = _M.shell.execute(cmd, c.shell.args)
    if not err then
        return out
    else
        return nil,err
    end
end

function _M.sanitize (obj)
    n_obj = {}
    if type(obj) == "string" then
        return obj:gsub("%s+$",""):gsub("^%s+",""):gsub("'","''")
    end
    for k,v in pairs(obj) do
        n_obj[k] = v:gsub("%s+$",""):gsub("^%s+",""):gsub("'","''")
    end
    return n_obj
end


function _M.get_key_details (data,fil)
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

function _M.get_cert_details (crt, fil)
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

function _M.file_from_data (data)
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

function _M.db_query (db_instance, query)
    local res, err, errcode, sqlstate = db_instance:query(query)
    if not res then
        ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
        return
    end
    return res
end

function _M.get_id_from_name (name,exit)
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

function _M.root_cert_override(v)
    if v.subject == v.issuer then
        -- root cert detected
        -- check for auth
        if ngx.var.arg_auth == c.security.root_auth then
            return true
        else
            return nil, "auth to upload root cert failed"
        end
    else
        return true
    end
end

function _M.add_to_db (type,obj)
    -- Adding acheck to uplad a root cert
    if type == 'cert' then
        local ok,err = _M.root_cert_override(obj)
        if not ok then
            _M.message_e("ERROR",err)
        end
    end
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

function _M.create_cert_chain (id,db,chain)
    -- Chain will contain the number of entries
    -- and should not be used while calling the function
    -- it is only for the purpose of recusrion
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
            -- We could not go till root cert, or 
            -- ended up in cycles, so, we return a false
            return chain, false
        elseif res[1]["issuer"] == subject then
            -- Not adding the root cert to the chain as
            -- there is no need for it there. To add it there
            -- we will only need t uncomment the next line
            -- also this will break the recursion
            -- table.insert(chain,res[1])
            -- returning the true means we have gone till
            -- root cert, will be helpful when we decide on checking
            -- cert usefulness
            return chain, true
        else
            -- keep going on till you go to either no res
            -- or a root cert
            table.insert(chain,res[1])
            return _M.create_cert_chain(id,db,chain)
        end
    end
end
-- clean up related functions
function _M.check_db_setup(db)
    -- check if table is created and has entries
   local q_test_if_table_exists_and_create = [[
CREATE table IF NOT EXISTS cert_status (
	id INT,
    cert_valid BOOL,
    last_change timestamp,
    PRIMARY KEY (id)
);
   ]]
   local res,err = _M.db_query(db,q_test_if_table_exists_and_create)
   if not res then
    _M.message_e("ERROR", err)
   end

   local q_create_cert_archive_if_not_exist = [[
    CREATE table IF NOT EXISTS ssl_certs_archive (
        id INT AUTO_INCREMENT,
        name text,
        last_change timestamp,
        expires timestamp,
        subject text,
        issuer text,
        raw text,
        fingerprint text,
        modulus_sha1 text,
        PRIMARY KEY (id)
    );
   ]]
   
   local res,err = _M.db_query(db,q_create_cert_archive_if_not_exist)
   if not res then
    _M.message_e("ERROR", err)
   end

   local q_create_key_archive_if_not_exist = [[
    CREATE table IF NOT EXISTS ssl_keys_archive (
        id INT AUTO_INCREMENT,
        name text,
        last_change timestamp,
        raw text,
        modulus_sha1 text,
        PRIMARY KEY (id)
    );
   ]]
   local res,err = _M.db_query(db,q_create_key_archive_if_not_exist)
   if not res then
    _M.message_e("ERROR", err)
   end

   return true
end

function _M.get_certs_to_be_validated(db)
    -- return a table containing the certs in array format
    -- (can directly give mysql query output)
    -- This is only for certs that need to be tested and those
    -- are the certs that have a key present
    local q_get_certs_to_be_validated = [[
        SELECT  c.id from ssl_certs c
        INNER JOIN ssl_keys k ON c.modulus_sha1 = k.modulus_sha1
        LEFT JOIN cert_status cs ON c.id = cs.id where cs.cert_valid = 0 or cs.cert_valid is NULL;
    ]]
    local res,err = _M.db_query(db,q_get_certs_to_be_validated)
    if not res then
     _M.message_e("ERROR", err)
    end
    return res
end

function _M.update_cert_status_in_db(id,val,db)
    -- we just need to say that the cert has complete chain or not
    local q_change_cert_valid_status_template = [[
        INSERT INTO cert_status
        (id, cert_valid, last_change)
        VALUES
        ({id}, {val}, '{time}')
    ON DUPLICATE KEY UPDATE
    cert_valid = VALUES(cert_valid),
    last_change = VALUES(last_change);
    ]]
    if val then
        local cmd = 'date -u +"%Y-%m-%d %H:%M:%S"'
        local status, out, err = _M.shell.execute(cmd, c.shell.args)
        local now = out
        local q_change_cert_valid_status = q_change_cert_valid_status_template:gsub("{id}",id):gsub("{val}",1):gsub("{time}",now)
        local res,err = _M.db_query(db,q_change_cert_valid_status)
        if not res then
            _M.message_e("ERROR", err)
        end
    end   
end

function _M.get_duplicate_certs(db)
    -- find duplicates and return list that can be archived
    local q_find_duplicate_certs = [[
        SELECT  c.id , c.name, IFNULL(cs.cert_valid,0) as cert_valid, UNIX_TIMESTAMP(c.expires) as expires from ssl_certs c
        INNER JOIN ssl_keys k ON c.modulus_sha1 = k.modulus_sha1
        LEFT JOIN cert_status cs on c.id = cs.id WHERE c.name IN (SELECT name
      FROM ssl_certs
      GROUP BY name
      HAVING COUNT(*) > 1)        
    ]]
    local res,err = _M.db_query(db,q_find_duplicate_certs)
    if not res then
        _M.message_e("ERROR", err)
    end
    return res
end

function _M.process_duplicate(cert)
    -- table to hold valid certs
    local v_certs = {}
    -- table to hold to archive certs
    local a_certs = {}
    for i,v in pairs(cert) do
        -- reducing table access complications and setting default where necessary
        local name = v["name"]
        local cert_valid = v["cert_valid"]
        local id = v["id"]
        local expires = v["expires"]
        _M.d(name)
        _M.d(cert_valid)
        _M.d(id)
        _M.d(expires)
        if not v_certs[name] then
            _M.d("c1")
            v_certs[name]={}
            v_certs[name][cert_valid]={}
            v_certs[name][cert_valid]["id"]=id
            v_certs[name][cert_valid]["ts"]=expires
        elseif v_certs[name] and not v_certs[name][cert_valid] then
            _M.d("c2")
            v_certs[name][cert_valid]={}
            v_certs[name][cert_valid]["id"]=id
            v_certs[name][cert_valid]["ts"]=expires
        elseif v_certs[name] and v_certs[name][cert_valid] and v_certs[name][cert_valid]["ts"] < expires then
            _M.d("c3")
            a_certs[#a_certs+1]=v_certs[name][cert_valid]["id"]
            v_certs[name][cert_valid]["id"]=id
            v_certs[name][cert_valid]["ts"]=expires
        else
            _M.d("c4")
            a_certs[#a_certs+1]=id
        end
    end
    for k,v in pairs(v_certs) do
        if v[1] and v[0] then
            a_certs[#a_certs+1]=v[0]["id"]
            v_certs[k][0]=nil
        end
    end
    for i,v in ipairs(a_certs) do
    _M.d(v)
    end
    return a_certs
end

function _M.get_unused_keys(db)
    local q_get_unused_keys = [[
        SELECT kid as id from (SELECT k.id as kid,c.id as cid from
ssl_keys k
LEFT JOIN
ssl_certs c
ON c.modulus_sha1 = k.modulus_sha1) AS T WHERE ISNULL(cid)
    ]]
    local res,err = _M.db_query(db,q_get_unused_keys)
        if not res then
            _M.message_e("ERROR", err)
    end
    return res
end

function _M.archive(type,id,db)
    --_M.d(type)
    --_M.de(id)
    -- archive cert/key with the associated id
    if type == "cert" then
        local q_archive_query_p_1 = [[
            INSERT INTO ssl_certs_archive
            SELECT *
            FROM ssl_certs
            WHERE id = {id} ;
        ]]
        local q_archive_query_p_2 = [[
            DELETE from ssl_certs
            WHERE id = {id};
        ]]
        local res,err = _M.db_query(db,q_archive_query_p_1:gsub("{id}",id))
        if not res then
            _M.message_e("ERROR", err)
        end
        local res,err = _M.db_query(db,q_archive_query_p_2:gsub("{id}",id))
        if not res then
            _M.message_e("ERROR", err)
        end
    elseif type == "key" then
        local q_archive_query_p_1 = [[
            INSERT INTO ssl_keys_archive
            SELECT *
            FROM ssl_keys
            WHERE id = {id} ;
        ]]
        local q_archive_query_p_2 = [[
            DELETE from ssl_keys
            WHERE id = {id};
        ]]
        local res,err = _M.db_query(db,q_archive_query_p_1:gsub("{id}",id))
        if not res then
            _M.message_e("ERROR", err)
        end
        local res,err = _M.db_query(db,q_archive_query_p_2:gsub("{id}",id))
        if not res then
            _M.message_e("ERROR", err)
        end
    end
end

return _M