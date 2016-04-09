do --- smoke
  assert(("abc123DEF_<>"):lower() == "abc123def_<>")
  assert(("abc123DEF_<>"):upper() == "ABC123DEF_<>")
end

do --- repeated
  local l = "the quick brown fox..."
  local u = "THE QUICK BROWN FOX..."
  local s = l
  for i = 1, 75 do
    s = s:upper()
    assert(s == u)
    s = s:lower()
    assert(s == l)
  end
end
