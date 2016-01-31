local grandparent = {}
grandparent.__newindex = function(s,_,_) tostring(s) end

local parent = {}
parent.__newindex = parent
parent.bar = 1
setmetatable(parent, grandparent)

local child = setmetatable({}, parent)
child.foo = _
