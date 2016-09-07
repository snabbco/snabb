local S = require("syscall")
local Tap = require("apps.tap.tap").Tap
local lib = require("core.lib")
local pcap = require("apps.pcap.pcap")
local pci = require("lib.hardware.pci")

function show_usage (code)
   print(require("program.tcpreplay.README_inc"))
   main.exit(code)
end

function parse_args (args)
   local handlers = {}
   local opts = {}
   function handlers.h ()
      show_usage(0)
   end
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "Duration must be a number")
   end
   args = lib.dogetopt(args, handlers, "hD:", { help="h", duration="D" })
   if #args ~= 2 then show_usage(1) end
   if not opts.duration then opts.duration = 1 end
   return opts, unpack(args)
end

-- TODO: Duplicated function. Move to a common place.
local function dir_exists (path)
   local stat = S.stat(path)
   return stat and stat.isdir
end

-- TODO: Duplicated function. Move to a common place.
local function nic_exists (pci_addr)
   local devices="/sys/bus/pci/devices"
   return dir_exists(("%s/%s"):format(devices, pci_addr)) or
      dir_exists(("%s/0000:%s"):format(devices, pci_addr))
end

function run (args)
   local opts, filein, iface = parse_args(args)
   local c = config.new()

   config.app(c, "pcap", pcap.PcapReader, filein)
   if nic_exists(iface) then
      local device_info = pci.device_info(iface)
      local driver = require(device_info.driver).driver
      config.app(c, "nic", driver, { pciaddr = iface })
      config.link(c, "pcap.output -> nic.rx")
   else
      config.app(c, "nic", Tap, iface)
      config.link(c, "pcap.output -> nic.input")
   end

   engine.configure(c)
   engine.main({duration=opts.duration})
end

-- Snabb shell cannot run a script that is a module, but it can run
-- a Lua script. However in that case 'args' variable is not present.
-- This function access directly to the command line argument list
-- and returns all script arguments. Script arguments are the arguments
-- after script name. Example: sudo ./snabb snsh <scriptname> ...
local function getargs()
   local scriptname = "tcpreplay.lua"
   local function basename (path)
      return path:gsub("(.*/)(.*)", "%2")
   end
   local function indexof (args, name)
      for i, arg in ipairs(args) do
         if basename(arg) == scriptname then
            return i
         end
      end
   end
   local args = main.parse_command_line()
   local index = assert(indexof(args, scriptname),
      "Scriptname is not in arguments list")
   -- Return arguments after scriptname.
   local ret = {}
   for i=index+1,#args do
      table.insert(ret, args[i])
   end
   return ret
end

run(getargs())
