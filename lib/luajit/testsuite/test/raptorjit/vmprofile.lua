local vmprofile = require("jit.vmprofile")

do --- vmprofile start and stop
   vmprofile.start()
   vmprofile.stop()
end


do --- vmprofile multiple starts
   for i = 1, 1000 do vmprofile.start() end
   vmprofile.stop()
end

do --- vmprofile multiple profiles
   vmprofile.start()
   local a = vmprofile.open("a.vmprofile")
   local b = vmprofile.open("b.vmprofile")
   vmprofile.select(a)
   for i = 1, 1e8 do end
   vmprofile.select(b)
   for i = 1, 1e8 do end
   vmprofile.select(a)
   for i = 1, 1e8 do end
   vmprofile.stop()
   vmprofile.close(a)
   vmprofile.close(b)
   -- simple sanity check that the profiles have different contents.
   -- e.g. to make sure there was at least one sample taken somewhere.
   assert(io.open("a.vmprofile", "r"):read("*a") ~=
             io.open("b.vmprofile", "r"):read("*a"),
          "check that profiles have different contents")
   os.remove("a.vmprofile")
   os.remove("b.vmprofile")
end
