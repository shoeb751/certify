#! /bin/sh
mkdir /tmp/luatmp
chown nobody: /tmp/luatmp
/bin/sockproc /tmp/sockproc.sock
chown nobody: /tmp/sockproc.sock
#TODO: SQL migrations are to be done here

# NSQD related configs
mkdir -p /opt/nsq/data
nsqd --data-path /opt/nsq/data 2>>/opt/nsq/nsq.err 1>>/opt/nsq/nsq.log &

/usr/local/openresty/bin/openresty -g "daemon off;"