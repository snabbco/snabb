
--fast, small recursive pretty printer with optional indentation and cycle detection.
--Written by Cosmin Apreutesei. Public Domain.

--pretty-printing of non-structured types

local type, tostring = type, tostring
local string_format, string_dump = string.format, string.dump
local math_huge, math_floor = math.huge, math.floor

local escapes = { --don't add unpopular escapes here
	['\\'] = '\\\\',
	['\t'] = '\\t',
	['\n'] = '\\n',
	['\r'] = '\\r',
}

local function escape_byte_long(c1, c2)
	return string_format('\\%03d%s', c1:byte(), c2)
end
local function escape_byte_short(c)
	return string_format('\\%d', c:byte())
end
local function quote_string(s, quote)
	s = s:gsub('[\\\t\n\r]', escapes)
	s = s:gsub(quote, '\\%1')
	s = s:gsub('([^\32-\126])([0-9])', escape_byte_long)
	s = s:gsub('[^\32-\126]', escape_byte_short)
	return s
end

local function format_string(s, quote)
	return string_format('%s%s%s', quote, quote_string(s, quote), quote)
end

local function write_string(s, write, quote)
	write(quote); write(quote_string(s, quote)); write(quote)
end

local keywords = {}
for i,k in ipairs{
	'and',       'break',     'do',        'else',      'elseif',    'end',
	'false',     'for',       'function',  'goto',      'if',        'in',
	'local',     'nil',       'not',       'or',        'repeat',    'return',
	'then',      'true',      'until',     'while',
} do
	keywords[k] = true
end

local function is_identifier(v)
	return type(v) == 'string' and not keywords[v]
				and v:find('^[a-zA-Z_][a-zA-Z_0-9]*$') ~= nil
end

local hasinf = math_huge == math_huge - 1
local function format_number(v)
	if v ~= v then
		return '0/0' --NaN
	elseif hasinf and v == math_huge then
		return '1/0' --writing 'math.huge' would not make it portable, just wrong
	elseif hasinf and v == -math_huge then
		return '-1/0'
	elseif v == math_floor(v) and v >= -2^31 and v <= 2^31-1 then
		return string_format('%d', v) --printing with %d is faster
	else
		return string_format('%0.17g', v)
	end
end

local function write_number(v, write)
	write(format_number(v))
end

local function is_dumpable(f)
	return type(f) == 'function' and debug.getinfo(f, 'Su').what ~= 'C'
end

local function format_function(f)
	return string_format('loadstring(%s)', format_string(string_dump(f, true)))
end

local function write_function(f, write, quote)
	write'loadstring('; write_string(string_dump(f, true), write, quote); write')'
end

local ffi, int64, uint64
local function is_int64(v)
	if type(v) ~= 'cdata' then return false end
	if not int64 then
		ffi = require'ffi'
		int64 = ffi.new'int64_t'
		uint64 = ffi.new'uint64_t'
	end
	return ffi.istype(v, int64) or ffi.istype(v, uint64)
end

local function format_int64(v)
	return tostring(v)
end

local function write_int64(v, write)
	write(format_int64(v))
end

local function format(v, quote)
	quote = quote or "'"
	if v == nil or type(v) == 'boolean' then
		return tostring(v)
	elseif type(v) == 'number' then
		return format_number(v)
	elseif type(v) == 'string' then
		return format_string(v, quote)
	elseif is_dumpable(v) then
		return format_function(v)
	elseif is_int64(v) then
		return format_int64(v)
	else
		error('unserializable', 0)
	end
end

local function is_serializable(v)
	return type(v) == 'nil' or type(v) == 'boolean' or type(v) == 'string'
				or type(v) == 'number' or is_dumpable(v) or is_int64(v)
end

local function pf_write(v, write, quote)
	quote = quote or "'"
	if v == nil or type(v) == 'boolean' then
		write(tostring(v))
	elseif type(v) == 'number' then
		write_number(v, write)
	elseif type(v) == 'string' then
		write_string(v, write, quote)
	elseif is_dumpable(v) then
		write_function(v, write, quote)
	elseif is_int64(v) then
		write_int64(v, write)
	else
		error('unserializable', 0)
	end
end

local function pretty(v, write, indent, parents, quote, onerror, depth, wwrapper)
	if is_serializable(v) then
		pf_write(v, write, quote)
	elseif getmetatable(v) and getmetatable(v).__pwrite then
		wwrapper = wwrapper or function(v)
			pretty(v, write, nil, parents, quote, onerror, -1, wwrapper)
		end
		getmetatable(v).__pwrite(v, write, wwrapper)
	elseif type(v) == 'table' then
		if parents then
			if parents[v] then
				write(onerror and onerror('cycle', v, depth) or 'nil --[[cycle]]')
				return
			end
			parents[v] = true
		end

		write'{'
		local maxn = 0; while rawget(v, maxn+1) ~= nil do maxn = maxn+1 end

		local first = true
		for k,v in pairs(v) do
			if not (maxn > 0 and type(k) == 'number' and k == math.floor(k) and k >= 1 and k <= maxn) then
				if first then first = false else write',' end
				if indent then write'\n'; write(indent:rep(depth)) end
				if is_identifier(k) then
					write(k); write'='
				else
					write'['; pretty(k, write, indent, parents, quote, onerror, depth + 1, wwrapper); write']='
				end
				pretty(v, write, indent, parents, quote, onerror, depth + 1, wwrapper)
			end
		end

		for k,v in ipairs(v) do
			if first then first = false else write',' end
			if indent then write'\n'; write(indent:rep(depth)) end
			pretty(v, write, indent, parents, quote, onerror, depth + 1, wwrapper)
		end

		if indent then write'\n'; write(indent:rep(depth-1)) end
		write'}'

		if parents then parents[v] = nil end
	else
		write(onerror and onerror('unserializable', v, depth) or
					string.format('nil --[[unserializable %s]]', type(v)))
	end
end

local function to_sink(write, v, indent, parents, quote, onerror, depth)
	return pretty(v, write, indent, parents, quote, onerror, depth or 1)
end

local function to_string(v, indent, parents, quote, onerror, depth)
	local buf = {}
	pretty(v, function(s) buf[#buf+1] = s end, indent, parents, quote, onerror, depth or 1)
	return table.concat(buf)
end

local function to_file(file, v, indent, parents, quote, onerror, depth)
	local f = assert(io.open(file, 'wb'))
	f:write'return '
	pretty(v, function(s) f:write(s) end, indent, parents, quote, onerror, depth or 1)
	f:close()
end

local function pp(...)
	local t = {}
	for i=1,select('#',...) do
		t[i] = to_string(select(i,...), '   ', {})
	end
	print(unpack(t))
	return ...
end

return setmetatable({
	write = to_sink,
	format = to_string,
	save = to_file,
	print = pp,
	pp = pp, --old API
}, {__call = function(self, ...)
	return pp(...)
end})
