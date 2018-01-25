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

local function format(indent, format, ...)
   for i = 1, indent do
      io.stdout:write(" ")
   end
   print(string.format(format, ...))
end

local function pci_stats(indent, path)
   local indent = indent or 0
   for _, pciaddr in ipairs(shm.children(path.."/pci")) do
      local pci = shm.open_frame(path.."/pci/"..pciaddr)
      local rxdrops_total = 0
      print()
      format(indent, "NIC %s", pciaddr)
      local qids = {}
      for _, file in ipairs(shm.children(path.."/pci/"..pciaddr)) do
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
         format(indent+2, "Queue #"..i)
         format(indent+4, "rxpackets         %s", read(pci[name..'rxpackets'], true))
         format(indent+4, "rxdrops           %s", comma_value(rxdrops))
         rxdrops_total = rxdrops_total + rxdrops
      end
      local rxpackets = read(pci.rxpackets)
      format(indent+2, "Total")
      format(indent+4, "rxpackets         %s", comma_value(rxpackets))
      format(indent+4, "rxdrops           %s (%1.4F%%)",
             comma_value(rxdrops_total),
             100*rxdrops_total/rxpackets)
      shm.delete_frame(pci)
   end
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
   local rss = {}
   if #args == 0 then
      for _, pid in ipairs(shm.children('/')) do
         if tonumber(pid) then
            for _, dir in ipairs(shm.children('/'..pid)) do
               if dir == 'ipfix_templates' then
                  table.insert(pids, tonumber(pid))
                  break
               end
            end
            for _, dir in ipairs(shm.children('/'..pid..'/apps')) do
               if dir == 'rss' then
                  local receivers = {}
                  for _, link in ipairs(shm.children('/'..pid..'/links')) do
                     repeat
                        if not link:match("^rss%..* -> +ipfix") then break end
                        local receiver = link:match(".* -> +([%w_]+)%.")
                        local id, type
                        if receiver:match("^ipfixmp") then
                           -- Receiver is connected through a
                           -- multi-process link
                           id = receiver:match("ipfixmp(%d+)")
                           type = 'pid'
                        else
                           -- Receiver is running in the same process
                           id = receiver:match("ipfix(%d+)")
                           type = 'instance'
                        end
                        table.insert(receivers,
                                     { id = id, type = type, link = link })
                     until true
                  end
                  table.insert(rss, { pid = tonumber(pid),
                                      receivers = receivers })
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
   table.sort(rss, function (a, b) return a.pid < b.pid end)

   for _, rss in ipairs(rss) do
      print()
      format(0, "RSS process #%d", rss.pid)
      pci_stats(2, '/'..rss.pid)
      print()
      format(2, "IPFIX receivers")
      table.sort(rss.receivers, function (a, b) return a.id < b.id end)
      for _, rcv in ipairs(rss.receivers) do
         if rcv.type == 'pid' then
            format(4, "Process #%d", rcv.id)
         else
            format(4, "Embedded instance #%d", rcv.id)
         end
         local stats = shm.open_frame('/'..rss.pid..'/links/'..rcv.link)
         local txpackets = read(stats.txpackets)
         local txdrop = read(stats.txdrop)
         format(6, "txpackets         %s", comma_value(txpackets))
         format(6, "txdrop            %s (%1.4F%%)",
                comma_value(txdrop),
                100*txdrop/txpackets)
         shm.delete_frame(stats)
      end
   end

   for _, pid in ipairs(pids) do
      print()
      format(0, "IPFIX process #%d", pid)
      local base_path = "/"..pid

      if #rss == 0 then
         pci_stats(2, base_path)
      end

      local instances = {}
      for _, app in ipairs(shm.children(base_path.."/apps")) do
         local instance =  app:match("^ipfix(%d)$")
         if instance then
            table.insert(instances, tonumber(instance))
         end
      end
      table.sort(instances)
      for _, instance in ipairs(instances) do
         local ipfix = shm.open_frame(base_path.."/apps/ipfix"..instance)
         print()
         format(2,"Instance #"..instance)
         format(4,"Version             %d", read(ipfix.version))
         format(4,"Observation domain  %d", read(ipfix.observation_domain))
         format(4,"Received packets    %s", read(ipfix.received_packets, true))
         format(4,"Ignored packets     %s", read(ipfix.ignored_packets, true))
         format(4,"Template packets    %s", read(ipfix.template_packets, true))
         format(4, "Sequence number     %s", read(ipfix.sequence_number, true))
         shm.delete_frame(ipfix)

         local templates = {}
         local path = base_path.."/ipfix_templates/"..instance
         for _, id in ipairs(shm.children(path)) do
            table.insert(templates, tonumber(id))
         end
         table.sort(templates)
         for _, id in ipairs(templates) do
            print()
            format(4,"Template #%d", id)
            local template = shm.open_frame(path.."/"..id)
            format(6, "Processed packets    %s",
                   read(template.packets_in, true))
            format(6, "Exported flows       %s",
                   read(template.exported_flows, true))
            format(6, "Flow export packets  %s",
                   read(template.flow_export_packets, true))
            local size = read(template.table_size)
            local occupancy = read(template.table_occupancy)
            local max_disp = read(template.table_max_displacement)
            format(6,"Table stats")
            format(8,"Occupancy          %s", comma_value(occupancy))
            format(8,"Size               %s", comma_value(size))
            format(8,"Byte size          %s", read(template.table_byte_size, true))
            format(8,"Load-factor        %1.2f", occupancy/size)
            format(8,"Max displacement   %d", max_disp)
            format(8,"Last scan time     %d", read(template.table_scan_time))
            shm.delete_frame(template)
            if shm.exists(path.."/"..id.."/stats") then
               format(6, "Template-specific stats")
               local stats = shm.open_frame(path.."/"..id.."/stats")
               for name, _ in pairs(stats.specs) do
                  format(8, "%-25s %s", name, read(stats[name], true))
               end
               shm.delete_frame(stats)
            end
         end
      end
   end
end
