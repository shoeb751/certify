#! /bin/sh
mkdir /tmp/luatmp
chown nobody: /tmp/luatmp
/bin/sockproc /tmp/sockproc.sock
chown nobody: /tmp/sockproc.sock
#TODO: SQL migrations are to be done here

/usr/local/openresty/bin/openresty -g "daemon off;"