--- table.new
do
  local tnew = require("table.new")
  local x, y
  for i=1,100 do
    x = tnew(100, 30)
    if i == 90 then y = x end
  end
  assert(x ~= y)
end

--- table.pack()
-- +lua52
do
  if os.getenv("LUA52") then
    local t = table.pack()
    assert(t.n == 0 and t[0] == nil and t[1] == nil)
  end
end

--- table.pack(99)
-- +lua52
do
  if os.getenv("LUA52") then
    local t = table.pack(99)
    assert(t.n == 1 and t[0] == nil and t[1] == 99 and t[2] == nil)
  end
end

--- table.pack(nils)
-- +lua52
do
  if os.getenv("LUA52") then
    local t = table.pack(nil, nil, nil)
    assert(t.n == 3 and t[0] == nil and t[1] == nil and t[2] == nil and t[3] == nil and t[4] == nil)
  end
end
