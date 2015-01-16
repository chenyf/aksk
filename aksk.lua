local MONGO = require "resty.mongol"
local JSON = require "cjson"
local UUID = require "resty.uuid"
local MD5 = require "resty.md5"
local STRING = require "resty.string"

DB_NAME = "aksk"
COL_NAME = "manager"

local router = require('mch.router')
router.setup()

map('.*', 'handler')

local function handler(req, resp)
	local conn = connectdb()
	if not conn then
		ngx.exit(500)
	end
	if req.method == 'GET' then
		code = get(req, resp, conn)
	elseif req.method == 'DELETE' then
		code = delete(req, resp, conn)
	elseif req.method == 'POST' then
		code = create(req, resp, conn)
	end
	conn:close()
	if code ~= 200 then
		ngx.exit(code)
	end
end

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

local function get(req, resp, conn)
    if not req.uri_args then
        return 404
	end
    local col = conn:new_db_handle(DB_NAME):get_col(COL_NAME)
    local r = col:find_one({ak=req.uri_args["ak"]}, {sk=1})
    if not r then
        return 404
	end
    resp:writeln(JSON.encode({sk=r["sk"]}))
	return 200
end

local function delete(req, resp, conn)
    local col = conn:new_db_handle(DB_NAME):get_col(COL_NAME)
    if req.uri_args then
        col:delete({ak=req.uri_args["ak"]})
    end
	return 200
end

local function create(req, resp, conn)
    req:read_body()
    if not req.post_args then
        return 400
	end
	m = JSON.decode(req.post_args)
	if not m then
		return 401
	end

    local token = m["sso_token"]
	if not token then
		return 401
	end

    local sk = UUID:generate()
    local md5 = MD5:new()
    md5:update(token)

    local ak = STRING.to_hex(md5:final())
    local sk = UUID:generate()
    local data = {}
    data["$set"] = {sk=sk}

    local col = conn:new_db_handle(DB_NAME):get_col(COL_NAME)
    local r, err = col:update({ak=ak}, data, 1, 0, true)
    if not r then
        ngx.log(ngx.ERR, "failed to gen aksk", err)
        return 500
	end
    resp:writeln(JSON.encode({ak=ak, sk=sk}))
	return 200
end

