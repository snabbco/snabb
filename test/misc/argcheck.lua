
local function check(f, msg)
  local ok, err = pcall(f)
  if ok then error("error check unexpectedly succeeded", 2) end
  if type(err) ~= "string" then
    error("error check failed with "..tostring(err), 2)
  end
  local line, err2 = string.match(err, ":(%d*): (.*)")
  if err2 ~= msg then error("error check failed with "..err, 2) end
end

assert(math.abs(-1.5) == 1.5)
assert(math.abs("-1.5") == 1.5)

check(function() math.abs() end,
      "bad argument #1 to 'abs' (number expected, got no value)")
check(function() math.abs(false) end,
      "bad argument #1 to 'abs' (number expected, got boolean)")
check(function() math.abs("a") end,
      "bad argument #1 to 'abs' (number expected, got string)")
string.abs = math.abs
check(function() ("a"):abs() end,
      "calling 'abs' on bad self (number expected, got string)")

assert(string.len("abc") == 3)
assert(string.len(123) == 3)

check(function() string.len() end,
      "bad argument #1 to 'len' (string expected, got nil)")
check(function() string.len(false) end,
      "bad argument #1 to 'len' (string expected, got boolean)")

assert(string.sub("abc", 2) == "bc")
assert(string.sub(123, "2") == "23")

check(function() string.sub("abc", false) end,
      "bad argument #2 to 'sub' (number expected, got boolean)")
check(function() ("abc"):sub(false) end,
      "bad argument #1 to 'sub' (number expected, got boolean)")

