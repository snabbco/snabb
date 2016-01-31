a = {}
i = 3
i, a[i] = i+1, 20
assert(i == 4)
assert(a[3] == 20)
