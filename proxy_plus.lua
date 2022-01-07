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

	args = ngx.req.get_uri_args()
	if args['_DOMAIN_'] then
		domain = args['_DOMAIN_']
		domain = domain:gsub("^_",""):gsub("_$","")
		args['_DOMAIN_'] = nil
		ngx.req.set_uri_args(args)
		return domain
	end

	return "www." .. ngx.var.PROXY_MAIN_DOMAIN
end

local cjson = require "cjson"
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
	local pattern = "[\"(][^\"(%?]+" .. old_domain .. "[^\")]*[\")]"
	local start = 0
	local eof = 0
	local replace_table = {}
	while true do
		if response_body:find(pattern,start+1) then
			start,eof = response_body:find(pattern,start+1)
			local match = response_body:sub(start,eof)
			replace_table[match] = start
		else break end
	end
	

	for full_url,match_start in pairs(replace_table) do
		local _,_,left,full_url,right = full_url:find("^([\"%(])(.*)([\"%)])")
		local status,decode_url,need_encode = pcall(decode,full_url)

		if status == false then
			print("undecode url:-------------------------------:",full_url)
			goto continue
		end

		local match_domain = decode_url:sub(decode_url:find("[%w-]+%." .. old_domain))	
		decode_url = decode_url:gsub(match_domain,new_domain .. "/_DOMAIN_=_" .. match_domain .. "_/")
		if is_https == false and decode_url:find("https") then
			decode_url = decode_url:gsub("https","http")
		end

		if need_encode==1 then
			decode_url = encode(decode_url)
		end
		full_url = escape_pattern(left .. full_url .. right)
		decode_url = left .. decode_url .. right
		decode_url = decode_url:gsub("%%", "%%%%")

		response_body = response_body:gsub(full_url,decode_url)

		::continue::
	end
	return response_body
end
function escape_pattern(str)
	str = str:gsub("[%(%)%.%%%+%-%*%?%[%^%$%]]", "%%%1")
	return str
end

function decode(full_url)
	if full_url:find("\\u") then
		local json_url = cjson.decode("{\"url\":\"" ..full_url..  "\"}")
		return json_url['url'],1
	else
		return full_url,0
	end
end

function encode(full_url)
	local encode_url = cjson.encode({url=full_url})
	return encode_url:gsub("{\"url\":\"",""):gsub("\"}","")
end

return _M
