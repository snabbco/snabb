
-- Basic goto and label semantics.
do
  local function expect(src, msg)
    local ok, err = loadstring(src)
    if msg then
      assert(not ok and string.find(err, msg))
    else
      assert(ok)
    end
  end

  -- Error: duplicate label.
  expect("::a:: ::a::", "'a'")
  expect("::a:: ::b:: do ::b:: end ::a::", "'a'")

  -- Error: undefined label.
  expect("goto a", "'a'")
  expect("goto a; ::b::", "'a'")
  expect("do ::a:: end; goto a", "'a'")
  expect("goto a; do ::a:: end", "'a'")
  expect("break", "break")
  expect("if x then break end", "break")

  -- Error: goto into variable scope.
  expect("goto a; local x; ::a:: local y", "'x'")
  expect("do local v,w; goto a; end; local x; ::a:: local y", "'x'")
  expect("repeat goto a; local x; ::a:: until x", "'x'")

  if os.getenv("LUA52") then
    expect("goto = 1", "<name>")
  else
    expect("goto = 1")
  end

  ::a:: do goto a; ::a:: end -- Forward jump, not an infinite loop.
end

-- Trailing label is considered to be out of scope.
do
  local x = 11
  do
    goto a
    goto a
    local y = 22
    x = y
    ::a::
    ::b::
  end
  assert(x == 11)
  if os.getenv("LUA52") then
    assert(loadstring([[
      local x = 11
      do
	goto a
	goto a
	local y = 22
	x = y
	::a:: ;;
	::b:: ;;
      end
      return x
    ]])() == 11)
  end
end

-- Simple loop with cross-jumping.
do
  local x = 1
  while true do
    goto b
    ::a:: if x < 100 then goto c end
    goto d
    ::b:: x = x + 1; goto a
    ::c::
  end
  ::d::
  assert(x == 100)
end

-- Backwards goto must close upval.
do
  local t = {}
  local i = 1
  ::a::
  local x
  t[i] = function() return x end
  x = i
  i = i + 1
  if i <= 2 then goto a end
  assert(t[1]() == 1)
  assert(t[2]() == 2)
end

-- Break must close upval, even if closure is parsed after break.
do
  local foo
  repeat
    local x
    ::a::
    if x then break end
    function foo() return x end
    x = true
    goto a
  until false
  assert(foo() == true)
end

-- Label prevents joining to KNIL.
do
  local k = 0
  local x
  ::foo::
  local y
  assert(y == nil)
  y = true
  k = k + 1
  if k < 2 then goto foo end
end

-- Break resolved from the right scope.
do
  local function p(lvl)
     lvl = lvl or 1
     while true do
	lvl = lvl + 1
	if lvl == nil then break end
	local idx = 1
	while true do
	   if key == nil then break end
	   idx = idx + 1
	end
     end
  end
end

-- Do not join twice with UCLO.
do
  while true do
    do
      local x
      local function f() return x end
    end
    break
  end

  while true do
    do
      local x
      local function f() return x end
    end
    goto foo
  end
  ::foo::
end

