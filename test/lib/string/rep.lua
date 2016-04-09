do --- smoke
  assert(("p"):rep(0) == "")
  assert(("a"):rep(3) == "aaa")
  assert(("x\0z"):rep(4) == "x\0zx\0zx\0zx\0z")
end

do --- versus concat
  local s = ""
  for i = 1, 75 do
    s = s .. "{}"
    assert(s == ("{}"):rep(i))
  end
end
