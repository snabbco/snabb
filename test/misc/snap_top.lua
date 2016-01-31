
do
  function randomtable(entries, depth)
    if depth == 0 then
      return tostring(math.random(2)) -- snapshot between return and CALLMT
    end
    local t = {}
    for k=1,entries do
      t[k] = randomtable(entries, depth-1)
    end
    return t
  end

  local t = randomtable(10, 2)
end

