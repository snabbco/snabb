-- script to run init.lua in a container for testing

-- creates a container and runs init in it, innit.

-- pushes an interface into the container, but only with local routing, not bridged or mac-vlan'd for now

-- run as root

local oldassert = assert
local function assert(c, s)
  return oldassert(c, tostring(s))
end

if not arg[1] then arg[1] = "root"

S.chdir(arg[1])

local p = assert(S.clone("newnet,newipc,newns,newpid,newuts"))

if p == 0 then -- child
  -- do we need to clean anything?

  assert(S.execve("/sbin/init", {"init"}, {}))
  S.exit("failure")
else -- parent


  assert(S.waitpid(-1, "clone"))
end
