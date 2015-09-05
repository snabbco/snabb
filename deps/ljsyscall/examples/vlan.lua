-- example of how to create a vlan using ljsyscall
-- not in the tests as it will mess up your interfaces and as far as I know you can only create vlans on physical interfaces

local nl = require "syscall.nl"

local interface = "eth0"
local vlan = 40
local name = interface .. "." .. tostring(vlan)

local i = assert(nl.interfaces())

local ii = i[interface]

if not ii then
  print("cannot find underlying interface")
  os.exit(1)
end

-- create

-- equivalent to
-- ip link add link eth0 name eth0.42 type vlan id 40

ok, err = nl.create_interface{name = name, link = ii.index, type = "vlan", id = vlan}

--Equivalent using newlink
--ok, err = nl.newlink(0, "create", 0, 0, "link", ii.index, "ifname", name, "linkinfo", {"kind", "vlan", "data", {"id", vlan}})

if not ok then
  print(err)
  os.exit(1)
end

i:refresh()

print(i)

ok, err = nl.dellink(0, "ifname", name)

if not ok then
  print(err)
  os.exit(1)
end


