local logger = {}

local log_levels = {"OFF", "FATAL", "ERROR", "WARN", "INFO", "DEBUG", "TRACE", "ALL"}

local log_enabled = {}

local function set_log_level(lvl)
    local enabled = false
    for i = #log_levels, 1, -1 do
        if log_levels[i] == lvl then
            enabled = true
        end
        log_enabled[log_levels[i]] = enabled
    end
    if not enabled then
        error("Log level not defined in library")
    end
end

local function index_function(t, k)
    -- t will be table on which we are trying key lookup
    -- k will be the key that is looked up
    local key = k:upper()
    if t.log_enabled[key] then
        return t.log_function(t, key)
    else
        return t.log_noop_function
    end
end

local function call_function(t, ...)
    t.info(...)
end

local function log_generic_implement(logger_fn)
    -- assumption is that logger_fn takes a list of
    -- values which concatenated together will
    -- be a logline
    -- It seemed like a better idea to let the
    -- other function work with table rather than
    -- passing a string, as this might lead to
    -- string copies, and the logger_fn gets a bit
    -- more power to play with the data
    local now = os.date("%Y-%m-%dT%H:%M:%S")
    -- local logtable = { ... }

    return function(...)
        local logtable = {...}
        for i, v in ipairs(logtable) do
            logtable[i] = string.gsub(tostring(v), '\n', ' ')
        end
        logger_fn(now, ngx.var.request_id, table.unpack(logtable))
    end
end

local function log_print_fn(...)
    -- takes ... as input
    local logline = table.concat({...}, ' ')
    print(logline)
end

local function log_nsqlog_fn(...)
    -- takes ... as input
    local logline = table.concat({...}, ' ')
    local producer = require "nsq.producer"
    local prod = producer:new()
    local ok, err = prod:connect("127.0.0.1", 4150)
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end
    ok, err = prod:pub("log", logline)
    if not ok then
        ngx.say("failed to pub: ", err)
        return
    end
    ok, err = prod:close()
    if not ok then
        ngx.say("failed to close: ", err)
        return
    end
end

local loggers = {
    log_print_fn = log_print_fn,
    log_nsqlog_fn = log_nsqlog_fn
}

local function log_function(t, k)
    return function(...)
        local f = log_generic_implement(t.logger_fn)(k, ...)
    end
end

local log_mt = {
    __index = index_function,
    __call = call_function
}

local log = {
    set_log_level = set_log_level,
    log_function = log_function,
    log_noop_function = function()
    end,
    log_enabled = log_enabled,
    logger_fn = log_print_fn,
    loggers = loggers
}
setmetatable(log, log_mt)

return log
