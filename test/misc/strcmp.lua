
do
  local a = "\255\255\255\255"
  local b = "\1\1\1\1"

  assert(a > b)
  assert(a > b)
  assert(a >= b)
  assert(b <= a)
end

