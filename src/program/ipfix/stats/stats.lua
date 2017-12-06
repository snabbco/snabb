module(..., package.seeall)

local shm = require("core.shm")
local counter = require("core.counter")
local lib = require("core.lib")

local pretty = true
local function comma_value(value)
   return pretty and lib.comma_value(value) or tostring(value)
end

local function read(c, cv)
   local n = tonumber(counter.read(c))
   return cv and comma_value(n) or n
end

local function format(format, ...)
   print(string.format(format, ...))
end

local long_opts = {
   help = "h",
}

function run (args)
   local opt = {
      h = function (arg)
         print(require("program.ipfix.stats.README_inc"))
         main.exit(0)
      end,
      n = function (arg)
         pretty = false
      end
   }
   args = lib.dogetopt(args, opt, "hn", long_opts)

   local pids = {}
   if #args == 0 then
      for _, pid in ipairs(shm.children('/')) do
         if tonumber(pid) then
            for _, dir in ipairs(shm.children('/'..pid)) do
               if dir == 'templates' then
                  table.insert(pids, tonumber(pid))
                  break
               end
            end
         end
      end
   else
      pids = args
   end

   if #pids == 0 then
      print("No IPFIX processes found")
      os.exit(0)
   end

   table.sort(pids)

   for _, pid in ipairs(pids) do
      format("\nIPFIX process #%d", pid)
      local base_path = "/"..pid
      local ipfix = shm.open_frame(base_path.."/apps/ipfix")
      format("Version             %d", read(ipfix.version))
      format("Observation domain  %d", read(ipfix.observation_domain))
      format("Received packets    %s", read(ipfix.received_packets, true))
      format("Ignored packets     %s", read(ipfix.ignored_packets, true))
      format("Template packets    %s", read(ipfix.template_packets, true))
      format("Sequence number     %s", read(ipfix.sequence_number, true))
      shm.delete_frame(ipfix)

      for _, pciaddr in ipairs(shm.children(base_path.."/pci")) do
         local pci = shm.open_frame(base_path.."/pci/"..pciaddr)
         local rxdrops_total = 0
         format("NIC %s", pciaddr)
         local qids = {}
         for _, file in ipairs(shm.children(base_path.."/pci/"..pciaddr)) do
            local base = file:match('(q[%d]+_rx_enabled)')
            if base then
               if read(pci[base]) == 1 then
                  local i = tonumber(file:match('q([%d]+)_'))
                  table.insert(qids, i)
               end
            end
         end
         table.sort(qids)
         for _, i in ipairs(qids) do
            local name = "q"..i.."_"
            local rxdrops = read(pci[name..'rxdrops'])
            format("  Queue #"..i)
            format("    rxpackets       %s", read(pci[name..'rxpackets'], true))
            format("    rxdrops         %s", comma_value(rxdrops))
            rxdrops_total = rxdrops_total + rxdrops
         end
         local rxpackets = read(pci.rxpackets)
         format("  Total")
         format("    rxpackets       %s", comma_value(rxpackets))
         format("    rxdrops         %s (%1.4F%%)",
                comma_value(rxdrops_total),
                100*rxdrops_total/rxpackets)
         shm.delete_frame(pci)
      end

      local templates = {}
      for _, id in ipairs(shm.children(base_path.."/templates")) do
         table.insert(templates, tonumber(id))
      end
      table.sort(templates)
      for _, id in ipairs(templates) do
         format("\nTemplate #%d", id)
         local template = shm.open_frame(base_path.."/templates/"..id)
         format("Processed packets    %s", read(template.packets_in, true))
         format("Exported flows       %s", read(template.exported_flows, true))
         format("Flow export packets  %s",
                read(template.flow_export_packets, true))
         local size = read(template.table_size)
         local occupancy = read(template.table_occupancy)
         local max_disp = read(template.table_max_displacement)
         format("Table stats")
         format("  Occupancy          %s", comma_value(occupancy))
         format("  Size               %s", comma_value(size))
         format("  Byte size          %s", read(template.table_byte_size, true))
         format("  Load-factor        %1.2f", occupancy/size)
         format("  Max displacement   %d", max_disp)
         format("  Last scan time     %d", read(template.table_scan_time))
         shm.delete_frame(template)
         if shm.exists(base_path.."/templates/"..id.."/stats") then
            format("Template-specific stats")
            local stats = shm.open_frame(base_path.."/templates/"..id.."/stats")
            for name, _ in pairs(stats.specs) do
               format("  %-25s %s", name, read(stats[name], true))
            end
            shm.delete_frame(stats)
         end
      end
   end
end
