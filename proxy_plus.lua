local _M = {}

function _M.before_proxy()
	local domain = nil
	local uri = ngx.var.uri
	if uri:find("_DOMAIN_") then
		local start,eof,domain = uri:find("_DOMAIN_=_([^_]+)_/")
		local domain_param = uri:sub(start,eof)
		uri = uri:gsub(escape_pattern(domain_param),"")
		ngx.req.set_uri(uri)
		ngx.req.set_uri_args("")
		return domain
	end
	
	return "www." .. ngx.var.PROXY_MAIN_DOMAIN
end

function _M.after_proxy()
	if ngx.header.content_type:find('text') == nil and ngx.header.content_type:find("application/javascript") == nil then
		return
	end

	local response_body = ngx.arg[1]
	local current_host = ngx.var.http_host

	local is_https = false
	if ngx.var.https == 'on' then
		is_https = true
	end
	response_body = _M.replace_domain(response_body,ngx.var.PROXY_MAIN_DOMAIN,current_host,is_https)
	ngx.arg[1] = response_body

end

function _M.replace_domain(response_body,old_domain,new_domain,is_https)
	local old_domain = old_domain:gsub("%.","%%.")
	-- Intend to capture all left char in regex,but lua meet performance problem when use ".-" in large text(length>5000)
	-- local pattern = "(.-[\"%(])([^\"%(]+" .. old_domain .. "[^\"%)]*)([\"%)])"
	local pattern = "([\"%(])([^\"%(]+" .. old_domain .. "[^\"%)]*)([\"%)])"
	local start,eof,last_eof = 0,0,0
	local new_response_body = ""
	local match_url,left,right,decode_url = nil,nil,nil,nil
	local response_table = {}

	while true do
		start,eof,left,match_url,right = response_body:find(pattern,eof+1)
		
		if start then
			local status,decode_url,need_encode = pcall(decode,match_url)
			if status then
				if is_https == false and decode_url:find("https") then
					decode_url = decode_url:gsub("https","http")
				end

				local _,_,proto,match_domain,uri = decode_url:find("(.-)([^/]*" .. old_domain .. ")(.*)")
				decode_url = proto .. new_domain .. "/_DOMAIN_=_" .. match_domain .. "_/" .. uri

				if need_encode==1 then
					decode_url = encode(decode_url)
				end
			else
				print("undecode url:-------------------------------:",match_url)
				decode_url = match_url
			end

			response_table[#response_table+1] = response_body:sub(last_eof+1,start-1)
			response_table[#response_table+1] = left
			response_table[#response_table+1] = decode_url
			response_table[#response_table+1] = right

			last_eof = eof

		else break end

	end

	response_table[#response_table+1] = response_body:sub(last_eof+1,-1)
	return table.concat(response_table,"")
	
end

function escape_pattern(str)
	str = str:gsub("[%(%)%.%%%+%-%*%?%[%^%$%]]", "%%%1")
	return str
end

local cjson = require "cjson"
local json_encode,json_decode = cjson.encode,cjson.decode
function decode(full_url)
	if full_url:find("\\u") then
		local json_url = json_decode("{\"url\":\"" ..full_url..  "\"}")
		return json_url['url'],1
	else
		return full_url,0
	end
end

function encode(full_url)
	local encode_url = json_encode({url=full_url})
	return encode_url:gsub("{\"url\":\"",""):gsub("\"}","")
end

return _M
