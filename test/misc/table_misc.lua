
-- ABC elim
do
  local s, t = {}, {}
  for i=1,100 do t[i] = 1 end
  for i=1,100 do s[i] = t end
  s[90] = {}
  local n = 100
  for i=1,n do s[i][i] = i end
end

-- TSETM
do
  local function f(a,b,c)
    return a,b,c
  end

  local t

  t = {(f(1,2,3))}
  assert(t[1] == 1 and t[2] == nil and t[3] == nil)

  t = {f(1,2,3)}
  assert(t[1] == 1 and t[2] == 2 and t[3] == 3 and t[4] == nil)
  t = {f(1,2,3),}
  assert(t[1] == 1 and t[2] == 2 and t[3] == 3 and t[4] == nil)

  t = {f(1,2,3), f(4,5,6)}
  assert(t[1] == 1 and t[2] == 4 and t[3] == 5 and t[4] == 6 and t[5] == nil)

  t = {
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
  f(2,3,4)}
  assert(t[255] == 1 and t[256] == 2 and t[257] == 3 and t[258] == 4 and t[259] == nil)
end

do
  local function f() return 9, 10 end
  for i=1,100 do t = { 1, 2, 3, f() } end
  assert(t[1] == 1 and t[2] == 2 and t[3] == 3 and t[4] == 9 and t[5] == 10 and
	 t[6] == nil)
end

-- table.new
do
  local tnew = require("table.new")
  local x, y
  for i=1,100 do
    x = tnew(100, 30)
    if i == 90 then y = x end
  end
  assert(x ~= y)
end

-- table.concat
do
  local t = {a=1,b=2,c=3,d=4,e=5}
  t[1] = 4
  t[3] = 6
  local ok, err = pcall(table.concat, t, "", 1, 3)
  assert(not ok and err:match("index 2 "))
  local q = {}
  for i=1,100 do q[i] = {9,8,7} end
  q[90] = t
  for i=1,100 do
    assert(pcall(table.concat, q[i], "", 1, 3) == (i ~= 90))
  end
  t[2] = 5 -- index 1 - 3 in hash part
  q[91] = {}
  q[92] = {9}
  for i=1,100 do q[i] = table.concat(q[i], "x") end
  assert(q[90] == "4x5x6")
  assert(q[91] == "")
  assert(q[92] == "9")
  assert(q[93] == "9x8x7")
end

-- table.concat must inhibit CSE and DSE
do
  local t = {1,2,3}
  local y, z
  for i=1,100 do
    y = table.concat(t, "x", 1, 3)
    t[2] = i
    z = table.concat(t, "x", 1, 3)
  end
  assert(y == "1x99x3")
  assert(z == "1x100x3")
end

do
  local y
  for i=1,100 do
    local t = {1,2,3}
    t[2] = 4
    y = table.concat(t, "x")
    t[2] = 9
  end
  assert(y == "1x4x3")
end

do
  local t = {[0]={}, {}, {}, {}}
  for i=1,30 do
    for j=3,0,-1 do
      t[j].x = t[j-1]
    end
  end
end

-- table.pack
if os.getenv("LUA52") then
  local t

  t = table.pack()
  assert(t.n == 0 and t[0] == nil and t[1] == nil)

  t = table.pack(99)
  assert(t.n == 1 and t[0] == nil and t[1] == 99 and t[2] == nil)

  t = table.pack(nil, nil, nil)
  assert(t.n == 3 and t[0] == nil and t[1] == nil and t[2] == nil and t[3] == nil and t[4] == nil)
end

