-- need to set a fixed request id for whole request to be used by logging

ngx.ctx.request_id = ngx.var.request_id
ngx.ctx.status = 200
ngx.ctx.res = {}