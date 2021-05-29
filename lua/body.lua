-- send out response
ngx.status=ngx.ctx.status
ngx.say(table.concat(ngx.ctx.res))