
do
  local y
  for i=1,100 do y = string.reverse("abc") end
  assert(y == "cba")
  local x = "abcd"
  for i=1,100 do y = string.reverse(x) end
  assert(y == "dcba")
  x = 1234
  for i=1,100 do y = string.reverse(x) end
  assert(y == "4321")
end

do
  local y
  for i=1,100 do y = string.upper("aBc9") end
  assert(y == "ABC9")
  local x = ":abCd+"
  for i=1,100 do y = string.upper(x) end
  assert(y == ":ABCD+")
  x = 1234
  for i=1,100 do y = string.upper(x) end
  assert(y == "1234")
end

do
  local y
  for i=1,100 do y = string.lower("aBc9") end
  assert(y == "abc9")
  local x = ":abcd+"
  for i=1,100 do y = string.lower(x) end
  assert(y == ":abcd+")
  x = 1234
  for i=1,100 do y = string.lower(x) end
  assert(y == "1234")
end

do
  local t, y = {}, {}
  for i=1,100 do t[i] = string.char(i, 16+i, 32+i) end
  for i=1,100 do t[i] = string.reverse(t[i]) end
  assert(t[100] == "\132\116\100")
  for i=1,100 do t[i] = string.reverse(t[i]) end
  for i=1,100 do assert(t[i] == string.char(i, 16+i, 32+i)) end
  for i=1,100 do y[i] = string.upper(t[i]) end
  assert(y[65] == "AQA")
  assert(y[97] == "AQ\129")
  assert(y[100] == "DT\132")
  for i=1,100 do y[i] = string.lower(t[i]) end
  assert(y[65] == "aqa")
  assert(y[97] == "aq\129")
  assert(y[100] == "dt\132")
end

do
  local y, z
  local x = "aBcDe"
  for i=1,100 do
    y = string.upper(x)
    z = y.."fgh"
  end
  assert(y == "ABCDE")
  assert(z == "ABCDEfgh")
end

do
  local y
  for i=1,100 do y = string.rep("a", 10) end
  assert(y == "aaaaaaaaaa")
  for i=1,100 do y = string.rep("ab", 10) end
  assert(y == "abababababababababab")
  for i=1,100 do y = string.rep("ab", 10, "c") end
  assert(y == "abcabcabcabcabcabcabcabcabcab")
  local x = "a"
  for i=1,100 do y = string.rep(x, 10) end
  assert(y == "aaaaaaaaaa")
  local n = 10
  for i=1,100 do y = string.rep(x, n) end
  assert(y == "aaaaaaaaaa")
  x = "ab"
  for i=1,100 do y = string.rep(x, n) end
  assert(y == "abababababababababab")
  x = 12
  n = "10"
  for i=1,100 do y = string.rep(x, n) end
  assert(y == "12121212121212121212")
end

do
  local t = {}
  for i=1,100 do t[i] = string.rep("ab", i-85) end
  assert(t[100] == "ababababababababababababababab")
  for i=1,100 do t[i] = string.rep("ab", i-85, "c") end
  assert(t[85] == "")
  assert(t[86] == "ab")
  assert(t[87] == "abcab")
  assert(t[100] == "abcabcabcabcabcabcabcabcabcabcabcabcabcabcab")
end

do
  local y, z
  local x = "ab"
  for i=1,100 do
    y = string.rep(x, i-90)
    z = y.."fgh"
  end
  assert(y == "abababababababababab")
  assert(z == "ababababababababababfgh")
end

