local MONGO = require "resty.mongol"
local JSON = require "cjson"
local UUID = require "resty.uuid"
local MD5 = require "resty.md5"
local STRING = require "resty.string"

DB_NAME = "aksk"
COL_NAME = "manager"

local function connectdb()
	local db_host = ngx.var.aksk_manager_host or "127.0.0.1"
	local db_port = ngx.var.aksk_manager_port or 27017

	local conn = MONGO:new()
	local ok, err = conn:connect(db_host, db_port)
	if not ok then
    	ngx.log(ngx.ERR, "failed to connect db: ", err)
	    return nil
	end
	return conn
end

local function onResponse(errno, errmsg, data, httpcode)
	local reply = {}
	reply.errno = errno
	if errmsg then reply.errmsg = errmsg end
	if data then reply.data = data end
   	ngx.say(JSON.encode(reply))
	return httpcode
end

-- POST /api/v1/app
local function addApp(conn)
    --ngx.req.read_body()
	--local data = ngx.req.get_body_data()
	--j = JSON.decode(data)
	--if not j then
    --    ngx.log(ngx.ERR, "invalid data: ", data)
	--	return 401
	--end
	local u1 = UUID:generate()
    local appid = "id_" .. u1
    u1 = UUID:generate()
    md5 = MD5:new()
    md5:update(u1)
    local ak = "ak_" .. STRING.to_hex(md5:final())
    
	u1 = UUID:generate()
    md5 = MD5:new()
    md5:update(u1)
    local sk = "sk_" .. STRING.to_hex(md5:final())

    local data = {appid=appid, ak=ak, sk=sk}
    local col = conn:new_db_handle(DB_NAME):get_col(COL_NAME)
	--local r, err = col:update({ak=ak}, doc, 1, 0, true)
    local r, err = col:insert({data}, false, true)
    if not r then
		return onResponse(10001, "internal error", nil, 500)
	end
	return onResponse(0, nil, data, 200)
end

-- DELETE /api/v1/app
local function delApp(conn)
	ngx.req.read_body()
	local data = ngx.req.get_body_data()
	j = JSON.decode(data)
	if not j then
		return onResponse(10001, "invalid POST data", nil, 401)
	end
	if not j["appid"] then
		return onResponse(10001, "missing 'appid'", nil, 401)
	end
    local col = conn:new_db_handle(DB_NAME):get_col(COL_NAME)
    col:delete({appid=args["appid"]})
	return onResponse(0, nil, nil, 200)
end

-- GET /api/v1/app
local function getApp(conn)
	args = ngx.req.get_uri_args()
    if not args then
		return onResponse(10001, "invalid GET args", nil, 401)
	end
	if not args["appid"] then
		return onResponse(10001, "missing 'appid'", nil, 401)
	end
    local col = conn:new_db_handle(DB_NAME):get_col(COL_NAME)
    local r = col:find_one({appid=args["appid"]}, {ak=1, sk=1})
    if not r then
		return onResponse(10001, "no such 'appid'", nil, 404)
	end
	data = {appid=args["appid"], ak=r["ak"], sk=r["sk"]}
	return onResponse(0, nil, data, 200)
end

-- GET /api/v1/aksk/check
local function checkAksk(conn)
	args = ngx.req.get_uri_args()
    if not args then
		return onResponse(10001, "invalid GET args", nil, 401)
	end
	if not args["appid"] or not args["ak"] or not args["sk"] then
		return onResponse(10001, "missing args", nil, 401)
	end
    local col = conn:new_db_handle(DB_NAME):get_col(COL_NAME)
    local r = col:find_one({appid=args["appid"], ak=args["ak"], sk=args["sk"]}, {ak=1, sk=1})
    if not r then
		return onResponse(0, nil, {result="0"}, 200)
	end
	return onResponse(0, nil, {resultl="1"}, 200)
end

local function handleApp(method, uri, conn)
	if method == 'POST' then
		code = addApp(conn)
	elseif method == 'DELETE' then
		code = delApp(conn)
	else
		onResponse(10001, "unsupport method", nil, 401)
		code = 401
	end
	return code
end

local function handleAksk(method, uri, conn)
	if method == 'GET' then
		code = checkAksk(conn)
	else
		onResponse(10001, "unsupport method", nil, 401)
		code = 401
	end
	return code
end

method = ngx.req.get_method()
uri = ngx.var.uri

router = {}
router["/api/v1/app"]        = handleApp
router["/api/v1/aksk/check"] = handleAksk

handler = router[uri]
if not handler then
	onResponse(10001, "unknown URI", nil, 404)
	ngx.exit(404)
end

local conn = connectdb()
if not conn then
	onResponse(10001, "internal error", nil, 500)
	ngx.exit(500)
end

code = handler(method, method, conn)
conn:close()
ngx.exit(code)

