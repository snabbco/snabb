a, b, c = 0, 1
assert(a == 0)
assert(b == 1)
assert(c == nil)
a, b = a+1, b+1, a+b
assert(a == 1)
assert(b == 2)
a, b, c = 0
assert(a == 0)
assert(b == nil)
assert(c == nil)
