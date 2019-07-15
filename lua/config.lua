_M = {}

_M.mysql = {
    auth = {
        host            = "db",
        port            = 3306,
        user            = "yui_u",
        password        = "yui_p",
        database        = "yui",
        charset         = "utf8",
        ssl             = true,
        max_packet_size = 1024 * 1024,
    },
    table = {
        cert  = "ssl_certs",
        key   = "ssl_keys",
    }
}
_M.shell = {
    args = {
        socket  = "unix:/tmp/sockproc.sock"
    }
}
_M.security = {
    root_auth = "test_auth"
}

return _M