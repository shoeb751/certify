local log = require "logger"

if not log.init then
    log.set_log_level("DEBUG")
    log.logger_fn=log.loggers.log_nsqlog_fn
    log.init = true
end

return log