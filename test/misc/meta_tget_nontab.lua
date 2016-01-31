
do
  local u = newproxy(true)
  getmetatable(u).__index = { foo = u, bar = 42 }

  local x = 0
  for i=1,100 do
    x = x + u.bar
    u = u.foo
  end
  assert(x == 4200)

  x = 0
  for i=1,100 do
    u = u.foo
    x = x + u.bar
  end
  assert(x == 4200)
end

do
  local s = "foo"
  string.s = s
  local x = 0
  local t = {}
  for i=1,100 do
    x = x + s:len()
    s = s.s
    t[s] = t -- Hash store with same type prevents hoisting
  end
  assert(x == 300)
end

