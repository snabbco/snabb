do --- BC_KNIL
  local function f(x, y) end
  for i = 1,100 do
    f(i, i)
    f(nil, nil)
  end
end
