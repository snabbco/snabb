-- example of how to create a vlan using ljsyscall
-- not in the tests as it will mess up your interfaces and as far as I know you can only create vlans on physical interfaces

local S = require "syscall"

local interface = "eth0"
local vlan = 40
local name = interface .. "." .. tostring(vlan)

local i = assert(S.interfaces())

local ii = i[interface]

if not ii then
  print("cannot find underlying interface")
  S.exit("failure")
end

-- create

-- trying to do    ip link add link eth0 name eth0.42 type vlan id 42
--ok, err = S.create_interface{name = name, type = "vlan", link = ii.index, vlan = vlan}
ok, err = S.newlink(0, S.NLM_F_CREATE, 0, 0, "link", ii.index, "ifname", name, "linkinfo", {"kind", "vlan", "data", "id", vlan})

if not ok then
  print(err)
  S.exit("failure")
end

i:refresh()

print(i)

ok, err = S.dellink(0, "ifname", name)

if not ok then
  print(err)
  S.exit("failure")
end


