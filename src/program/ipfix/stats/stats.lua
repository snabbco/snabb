-- Display statistics for IPFIX processes

-- XXX Re-write needed
module(..., package.seeall)

local shm = require("core.shm")
local counter = require("core.counter")
local lib = require("core.lib")
local S = require("syscall")

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

local function ppid_from_group (pid)
   local ppid
   local group = shm.root.."/"..shm.resolve("/"..pid.."/group")
   local stat = assert(S.lstat(group))
   if stat.islnk then
      ppid = S.readlink(group):match("/(%d+)/group")
   end
   return ppid
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

      if #qids == 0 then
         rxdrops_total = read(pci['rxdrop'])
      else
         for _, i in ipairs(qids) do
            local name = "q"..i.."_"
            local rxdrops = read(pci[name..'rxdrops'])
            format(indent+2, "Queue #"..i)
            format(indent+4, "rxpackets         %s", read(pci[name..'rxpackets'], true))
            format(indent+4, "rxdrops           %s", comma_value(rxdrops))
            rxdrops_total = rxdrops_total + rxdrops
         end
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

local function ipfix_info(pid)
   local path = '/'..pid
   local link, err = S.readlink(shm.root.."/"..shm.resolve(path..'/group'))
   if err then
      return { pid = pid }
   end
   local link
   for _, name in ipairs(shm.children(path
                                      .."/interlink/receiver")) do
      link = name:match("(.*).interlink")
      break
   end
   return { pid = pid, link = link }
end

local function rss_info(pid)
   local path = '/'..pid
   local interlinks = {}
   if shm.exists(path..'/interlink') then
      for _, name in ipairs(shm.children(path
                                         .."/interlink/transmitter")) do
         local link = name:match("(.*).interlink")
         interlinks[link] = true
      end
   end
   local receivers = {}
   for _, link in ipairs(shm.children(path..'/links')) do
      repeat
         if not link:match("^rss%.") then break end
         local id, type
         local receiver = link:match(".* -> +([%w_]+)%.")
         if interlinks[receiver] then
            -- Receiver is connected through a
            -- multi-process link
            type = 'interlink'
            -- Will be translated into a process ID later
            id = receiver
         else
            -- Receiver is running in the same process
            type = 'instance'
            id = tonumber(receiver:match("ipfix(%d+)"))
         end
         table.insert(receivers,
                      { id = id, type = type, link = link })
      until true
   end
   return { pid = pid, receivers = receivers }
end

local function usage()
   print(require("program.ipfix.stats.README_inc"))
   main.exit(0)
end

local long_opts = {
   help = "h",
}

function run (args)
   local opt = {
      h = function (arg)
         usage()
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
            table.insert(pids, pid)
         end
      end
   else
      pids = args
   end

   local ipfix = {}
   local rss = {}
   local ctrls = {}

   for _, pid in ipairs(pids) do
      if not shm.exists('/'..pid.."/config-worker-channel") then
	goto continue
      end
      for _, dir in ipairs(shm.children('/'..pid)) do
         if dir == 'ipfix_templates' then
            table.insert(ipfix, ipfix_info(tonumber(pid)))
            local ppid = ppid_from_group(pid)
            if ppid then
               ctrls[ppid] = true
            end
            break
         end
      end
      for _, dir in ipairs(shm.children('/'..pid..'/apps')) do
         if dir == 'rss' then
            table.insert(rss, rss_info(tonumber(pid)))
            local ppid = ppid_from_group(pid)
            if ppid then
               ctrls[ppid] = true
            end
         end
      end
      ::continue::
   end

   if #ipfix == 0 then
      print("No IPFIX processes found")
      os.exit(0)
   end

   local function by_pid(a, b)
      return a.pid < b.pid
   end
   table.sort(ipfix, by_pid)
   table.sort(rss, by_pid)

   -- Get PIDs of interlink receivers
   local function pid_from_link(link, ppid)
      for _, ipfix in ipairs(ipfix) do
         if ipfix.link == link then
            return ipfix.pid
         end
      end
   end
   for _, rss in ipairs(rss) do
      for _, r in ipairs(rss.receivers) do
         if r.type == "interlink" then
            r.id = pid_from_link(r.id, rss.pid)
         end
      end
   end

   for ppid, _ in pairs(ctrls) do
      print()
      format(0, "Control process #%d", ppid)
      pci_stats(2, '/'..ppid)
      print()
   end

   for _, rss in ipairs(rss) do
      print()
      format(0, "RSS process #%d", rss.pid)
      pci_stats(2, '/'..rss.pid)
      print()
      format(2, "IPFIX receivers")
      table.sort(rss.receivers, function (a, b) return a.id < b.id end)
      for _, rcv in ipairs(rss.receivers) do
         if rcv.type == 'interlink' then
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

   for _, ipfix in ipairs(ipfix) do
      print()
      format(0, "IPFIX process #%d", ipfix.pid)
      local base_path = "/"..ipfix.pid

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

            local function table_stats(prefix, title)
               local function get(name)
                  return  template[prefix..'_'..name]
               end
               local size = read(get('size'))
               local occupancy = read(get('occupancy'))
               local max_disp = read(get('max_displacement'))
               format(6,title )
               format(8,"Occupancy          %s", comma_value(occupancy))
               format(8,"Size               %s", comma_value(size))
               format(8,"Byte size          %s", read(get('byte_size'), true))
               format(8,"Load-factor        %1.2f", occupancy/size)
               format(8,"Max displacement   %d", max_disp)
               if template[prefix..'_scan_time'] then
                  format(8,"Last scan time     %d", read(get('scan_time')))
               end
            end
            table_stats('table', 'Table stats')
            if read(template.rate_table_size) > 0 then
               table_stats('rate_table', 'Export Flow-Rate Table stats')
            end
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
