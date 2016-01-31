
local function check(m, expected)
  local t = {}
  for k in pairs(m) do t[#t+1] = tostring(k) end
  table.sort(t)
  local got = table.concat(t, ":")
  if got ~= expected then
    error("got: \""..got.."\"\nexpected: \""..expected.."\"", 2)
  end
end

local bit = bit
_G.bit = nil
_G.jit = nil
table.setn = nil
package.searchpath = nil

if os.getenv("LUA52") then
  check(_G, "_G:_VERSION:arg:assert:collectgarbage:coroutine:debug:dofile:error:gcinfo:getfenv:getmetatable:io:ipairs:load:loadfile:loadstring:math:module:newproxy:next:os:package:pairs:pcall:print:rawequal:rawget:rawlen:rawset:require:select:setfenv:setmetatable:string:table:tonumber:tostring:type:unpack:xpcall")
  check(math, "abs:acos:asin:atan:atan2:ceil:cos:cosh:deg:exp:floor:fmod:frexp:huge:ldexp:log:log10:max:min:modf:pi:pow:rad:random:randomseed:sin:sinh:sqrt:tan:tanh")
  check(string, "byte:char:dump:find:format:gmatch:gsub:len:lower:match:rep:reverse:sub:upper")
  check(table, "concat:foreach:foreachi:getn:insert:maxn:pack:remove:sort:unpack")
else
  check(_G, "_G:_VERSION:arg:assert:collectgarbage:coroutine:debug:dofile:error:gcinfo:getfenv:getmetatable:io:ipairs:load:loadfile:loadstring:math:module:newproxy:next:os:package:pairs:pcall:print:rawequal:rawget:rawset:require:select:setfenv:setmetatable:string:table:tonumber:tostring:type:unpack:xpcall")
  check(math, "abs:acos:asin:atan:atan2:ceil:cos:cosh:deg:exp:floor:fmod:frexp:huge:ldexp:log:log10:max:min:mod:modf:pi:pow:rad:random:randomseed:sin:sinh:sqrt:tan:tanh")
  check(string, "byte:char:dump:find:format:gfind:gmatch:gsub:len:lower:match:rep:reverse:sub:upper")
  check(table, "concat:foreach:foreachi:getn:insert:maxn:remove:sort")
end

check(io, "close:flush:input:lines:open:output:popen:read:stderr:stdin:stdout:tmpfile:type:write")

check(debug.getmetatable(io.stdin), "__gc:__index:__tostring:close:flush:lines:read:seek:setvbuf:write")

check(os, "clock:date:difftime:execute:exit:getenv:remove:rename:setlocale:time:tmpname")

if os.getenv("LUA52") then
  check(debug, "debug:getfenv:gethook:getinfo:getlocal:getmetatable:getregistry:getupvalue:getuservalue:setfenv:sethook:setlocal:setmetatable:setupvalue:setuservalue:traceback:upvalueid:upvaluejoin")
else
  check(debug, "debug:getfenv:gethook:getinfo:getlocal:getmetatable:getregistry:getupvalue:setfenv:sethook:setlocal:setmetatable:setupvalue:traceback:upvalueid:upvaluejoin")
end

check(package, "config:cpath:loaded:loaders:loadlib:path:preload:seeall")

check(package.loaders, "1:2:3:4")
package.loaded.bit = nil
package.loaded.jit = nil
package.loaded["jit.util"] = nil
package.loaded["jit.opt"] = nil
check(package.loaded, "_G:coroutine:debug:io:math:os:package:string:table")

if bit then
  check(bit, "arshift:band:bnot:bor:bswap:bxor:lshift:rol:ror:rshift:tobit:tohex")
end

local ok, ffi = pcall(require, "ffi")
if ok then
  check(ffi, "C:abi:alignof:arch:cast:cdef:copy:errno:fill:gc:istype:load:metatype:new:offsetof:os:sizeof:string:typeinfo:typeof")
end

assert(math.pi == 3.141592653589793)
assert(math.huge > 0 and 1/math.huge == 0)
assert(debug.getmetatable("").__index == string)

