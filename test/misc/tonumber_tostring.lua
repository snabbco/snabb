
do
  local x = 0
  for i=1,100 do x = x + tonumber(i) end
  assert(x == 5050)
end

do
  local x = 0
  for i=1.5,100.5 do x = x + tonumber(i) end
  assert(x == 5100)
end

do
  local t = {}
  for i=1,100 do t[i] = tostring(i) end
  local x = 0
  for i=1,100 do assert(type(t[i]) == "string"); x = x + tonumber(t[i]) end
  assert(x == 5050)
end

do
  local t = {}
  for i=1,100 do t[i] = tostring(i+0.5) end
  local x = 0
  for i=1,100 do assert(type(t[i]) == "string"); x = x + tonumber(t[i]) end
  assert(x == 5100)
end

do
  for i=1,100 do assert(tonumber({}) == nil) end
end

do
  local t = {}
  for i=1,100 do t[i] = tostring(i) end
  for i=1,100 do t[i] = tostring(t[i]) end
  local x = 0
  for i=1,100 do assert(type(t[i]) == "string"); x = x + t[i] end
  assert(x == 5050)
end

do
  local mt = { __tostring = function(t) return tostring(t[1]) end }
  local t = {}
  for i=1,100 do t[i] = setmetatable({i}, mt) end
  for i=1,100 do t[i] = tostring(t[i]) end
  local x = 0
  for i=1,100 do assert(type(t[i]) == "string"); x = x + t[i] end
  assert(x == 5050)
end

do
  local r = setmetatable({},
			 { __call = function(x, t) return tostring(t[1]) end })
  local mt = { __tostring = r }
  local t = {}
  for i=1,100 do t[i] = setmetatable({i}, mt) end
  for i=1,100 do t[i] = tostring(t[i]) end
  local x = 0
  for i=1,100 do assert(type(t[i]) == "string"); x = x + t[i] end
  assert(x == 5050)
end

do
  local x = false
  local co = coroutine.create(function() print(1) end)
  debug.setfenv(co, setmetatable({}, { __index = {
    tostring = function() x = true end }}))
  coroutine.resume(co)
  assert(x == true)
end

do
  assert(tonumber(111, 2) == 7)
end

do
  local t = setmetatable({}, { __tostring = "" })
  assert(pcall(function() tostring(t) end) == false)
end

