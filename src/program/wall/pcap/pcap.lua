module(..., package.seeall)

local lib = require("core.lib")

local long_opts = {
   help  = "h";
}

function run (args)
   local opt = {
      h = function (arg)
         print(require("program.wall.pcap.README_inc"))
         main.exit(0)
      end;
   }

   args = lib.dogetopt(args, opt, "hi:", long_opts)
   if #args ~= 1 then
      print(require("program.wall.pcap.README_inc"))
      main.exit(1)
   end

   print("Not yet implemented")  -- TODO
end
