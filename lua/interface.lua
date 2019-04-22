local f = io.open('/mnt/c/Users/shoeb.c/Documents/Work/git/yui/ssl_storage/lua/list.html','r')
local k = f:read('*a')
f:close()
ngx.header['Content-Type']= 'text/html'
ngx.say(k)