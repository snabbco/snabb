-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local S = require("syscall")
local lib = require("core.lib")
local shm = require("core.shm")
local counter = require("core.counter")
local histogram = require("core.histogram")
local usage = require("program.top.README_inc")
local ethernet = require("lib.protocol.ethernet")
local file = require("lib.stream.file")
local fiber = require("lib.fibers.fiber")
local sleep = require("lib.fibers.sleep")
local op = require("lib.fibers.op")
local cond = require("lib.fibers.cond")
local channel = require("lib.fibers.channel")
local inotify = require("lib.ptree.inotify")
local rrd = require("lib.rrd")

-- First, the global state for the app.
--
local snabb_state = { instances={}, counters={}, histograms={}, rrds={} }
local ui = {
   view='interface',
   sample_time=nil, sample=nil, prev_sample_time=nil, prev_sample=nil,
   tree=nil, focus=nil, wake=cond.new(), rows=24, cols=80,
   show_empty=false, show_rates=true,
   show_links=true, show_apps=true, show_engine=true,
   pause_time=nil }

local function needs_redisplay(keep_tree)
   if not keep_tree then ui.tree = nil end
   ui.wake:signal()
end

-- Now the core code that monitors /var/run/snabb and updates
-- snabb_state.
--
local function is_dir(name)
   local stat = S.lstat(name)
   return stat and stat.isdir
end

local function dirsplit(name)
   return name:match("^(.*)/([^/]+)$")
end

local function instance_monitor()
   local tx = channel.new()
   local by_name_root = shm.root..'/by-name'
   local by_pid = inotify.directory_inventory_events(shm.root)
   local by_name = inotify.directory_inventory_events(by_name_root)
   local either = op.choice(by_pid:get_operation(), by_name:get_operation())
   fiber.spawn(function()
      local by_pid, by_name = {}, {}
      for event in either.perform, either do
         if event.kind == 'mkdir' or event.kind == 'rmdir' then
            -- Ignore; this corresponds to the directories being monitored.
         elseif event.kind == 'add' then
            local dirname, basename = dirsplit(event.name)
            if dirname == shm.root then
               local pid = tonumber(basename)
               if pid and is_dir(event.name) and not by_pid[pid] and pid ~= S.getpid() then
                  by_pid[pid] = {name=nil}
                  tx:put({kind="new-instance", pid=pid})
               end
            elseif dirname == by_name_root then
               local pid_dir = S.readlink(event.name)
               if pid_dir then
                  local root, pid_str = dirsplit(pid_dir)
                  local pid = pid_str and tonumber(pid_str)
                  if pid and root == shm.root and not by_name[basename] then
                     by_name[basename] = pid
                     tx:put({kind="new-name", name=basename, pid=pid})
                  end
               end
            end
         elseif event.kind == 'remove' then
            local dirname, basename = dirsplit(event.name)
            if dirname == shm.root then
               local pid = tonumber(basename)
               if pid and by_pid[pid] then
                  by_pid[pid] = nil
                  tx:put({kind="instance-gone", pid=pid})
               end
            elseif dirname == by_name_root then
               local pid = by_name[basename]
               if pid then
                  by_name[basename] = nil
                  tx:put({kind="name-gone", name=basename, pid=pid})
               end
            end
         else
            println('unexpected event: %s', event.kind, name)
         end
      end
   end)
   return tx
end

local function monitor_snabb_instance(pid, instance, counters, histograms, rrds)
   local dir = shm.root..'/'..pid
   local rx = inotify.recursive_directory_inventory_events(dir)
   local rx_op = rx:get_operation()
   fiber.spawn(function ()
      while true do
         local event = rx_op:perform()
         if event == nil then break end
         local name = event.name:sub(#dir + 2):match('^(.*)%.counter$')
         if name then
            if event.kind == 'creat' then
               local ok, c = pcall(counter.open, event.name:sub(#shm.root+1))
               if ok then counters[name] = c end
               needs_redisplay()
            elseif event.kind == 'rm' then
               pcall(counter.delete, counters[name])
               counters[name] = nil
               needs_redisplay()
            end
         elseif event.name == dir..'/group' then
            local target = S.readlink(event.name)
            if target and event.kind == 'creat' then
               local dir, group = dirsplit(target)
               local root, pid = dirsplit(dir)
               instance.group = tonumber(pid)
            else
               instance.group = nil
            end
            needs_redisplay()
         elseif event.name:match('%.histogram$') then
            local name = event.name:sub(#dir + 2):match('^(.*)%.histogram')
            if event.kind == 'creat' then
               local ok, h = pcall(histogram.open, event.name:sub(#shm.root+1))
               if ok then histograms[name] = h end
               needs_redisplay()
            elseif event.kind == 'rm' then
               -- FIXME: no delete!
               -- pcall(histogram.delete, counters[name])
               histograms[name] = nil
               needs_redisplay()
            end
         elseif event.name:match('%.rrd') then
            local name = event.name:sub(#dir + 2):match('^(.*)%.rrd')
            if event.kind == 'creat' then
               local ok, r = pcall(rrd.open_file, event.name)
               if ok then rrds[name] = r end
               needs_redisplay()
            elseif event.kind == 'rm' then
               rrds[name] = nil
               needs_redisplay()
            end
         end
      end
   end)
end

local function update_snabb_state()
   local rx = instance_monitor()
   local pending = {}
   local instances = snabb_state.instances
   local counters, histograms = snabb_state.counters, snabb_state.histograms
   local rrds = snabb_state.rrds
   for event in rx.get, rx do
      local kind, name, pid = event.kind, event.name, event.pid
      if kind == 'new-instance' then
         instances[pid], pending[pid] = { name = pending[pid] }, nil
         counters[pid], histograms[pid], rrds[pid] = {}, {}, {}
         monitor_snabb_instance(pid, instances[pid], counters[pid],
                                histograms[pid], rrds[pid])
      elseif kind == 'instance-gone' then
         instances[pid], pending[pid] = nil, nil
         counters[pid], histograms[pid], rrds[pid] = nil, nil, nil
         if ui.focus == pid then ui.focus = nil end
      elseif kind == 'new-name' then
         if instances[pid] then instances[pid].name = name
         else pending[pid] = name end
      elseif kind == 'name-gone' then
         instances[pid].name, pending[pid] = nil, nil
      end
      needs_redisplay()
   end
end

-- Now we start on the UI.  First, here are some low-level interfaces
-- for working with terminals.
--
local function clearterm () io.write('\027[2J') end
local function move(x,y)    io.write(string.format('\027[%d;%dH', x, y)) end
local function dsr()        io.write(string.format('\027[6n')) end
local function newline()    io.write('\027[K\027[E') end
local function printf(fmt, ...) io.write(fmt:format(...)) end
local function println(fmt, ...) printf(fmt, ...); newline(); io.flush() end
local function sgr(fmt,...) io.write('\027['..fmt:format(...)..'m') end
local function scroll(n)    io.write(string.format('\027[%dS', n)) end

local function bgcolordefault(n) sgr('49') end
local function fgcolordefault(n) sgr('39') end
local function bgcolor8(n) sgr('48;5;%d', n) end
local function fgcolor8(n) sgr('38;5;%d', n) end
local function bgcolor24(r,g,b) sgr('48;2;%d;%d;%d', r, g, b) end
local function fgcolor24(r,g,b) sgr('38;2;%d;%d;%d', r, g, b) end

local function request_dimensions() move(1000, 1000); dsr(); io.flush() end

local function makeraw (tc)
   local ret = S.t.termios()
   ffi.copy(ret, tc, ffi.sizeof(S.t.termios))
   ret:makeraw()
   return ret
end

-- Since we put the terminal into raw mode, we'll need to associate
-- functionality for all keys, and also handle all the escape sequences.
-- Here we set up key binding tables.
--
local function make_key_bindings(default_binding)
   local ret = {}
   for i=0,255 do ret[string.char(i)] = default_binding end
   return ret
end
local function bind_keys(k, f, bindings)
   if bindings == nil then bindings = global_key_bindings end
   for i=1,#k do bindings[k:sub(i,i)] = f end
end

local function debug_keypress(c)
   println('read char: %s (%d)', c, string.byte(c))
end
global_key_bindings = make_key_bindings(debug_keypress)

do
   local function unknown_csi(kind, ...)
      println('unknown escape-[: %s (%d)', kind, string.byte(kind))
   end
   csi_key_bindings = make_key_bindings(unknown_csi)
   local function csi_current_position(kind, rows, cols)
      ui.rows, ui.cols = rows or 24, cols or 80
      needs_redisplay(true)
   end
   bind_keys("R", csi_current_position, csi_key_bindings)

   escape_key_bindings = make_key_bindings(fiber.stop)
   local function unknown(c)
      println('unknown escape sequence: %s (%d)', c, string.byte(c))
   end
   for i=0x40,0x5f do
      bind_keys(string.char(i), unknown, escape_key_bindings)
   end

   local function read_int()
      local ret = 0
      for c in io.stdin.peek_char, io.stdin do
         local dec = c:byte() - ("0"):byte()
         if 0 <= dec and dec <= 9 then
            io.stdin:read_char()
            ret = ret * 10 + dec
         else
            return ret
         end
      end
   end
   local function csi()
      local args = {}
      while true do
         local ch = io.stdin:peek_char()
         if not ch then break end
         if not ch:match('[%d;]') then break end
         table.insert(args, read_int())
         if io.stdin:peek_char() == ';' then io.stdin:read_char() end
      end
      -- FIXME: there are some allowable characters here.
      local kind = io.stdin:read_char()
      csi_key_bindings[kind](kind, unpack(args))
   end
   bind_keys("[", csi, escape_key_bindings)

   local function escape_sequence()
      if io.stdin.rx:is_empty() then
         -- In theory we should see if stdin is readable, and if not wait
         -- for a small timeout.  However since the input buffer is
         -- relatively large, it's unlikey that we'd read an ESC without
         -- more bytes unless it's the user wanting to quit the program.
         return fiber.stop()
      end
      local kind = io.stdin:read_char()
      escape_key_bindings[kind](kind)
   end
   bind_keys("\27", escape_sequence)
end

-- React to SIGWINCH by telling the terminal to give us its dimensions
-- via the CSI current position escape sequence.
local function monitor_sigwinch()
   local f = file.fdopen(assert(S.signalfd("winch")))
   S.sigprocmask("block", "winch")
   local buf = ffi.new('uint8_t[128]')
   while f:read_some_bytes(buf, 128) > 0 do
      request_dimensions()
   end
end

-- Right!  So we have machinery to know what Snabb instances there are,
-- and we have basic primitives for input and output.  The plan is that
-- we'll write functions for rendering the state to the screen; here we
-- go!
--
local function sortedpairs(t)
   local keys = {}; for k,_ in pairs(t) do table.insert(keys, k) end
   table.sort(keys)
   local f, s, i = ipairs(keys)
   return function()
      local k
      i, k = f(s, i)
      if i then return k, t[k] end
   end
end

local function summarize_histogram(histogram, prev)
   local total = histogram.total
   if prev then total = total - prev.total end
   if total == 0 then return 0, 0, 0 end
   local min, max, cumulative = nil, 0, 0
   for count, lo, hi in histogram:iterate(prev) do
      if count ~= 0 then
	 if not min then min = lo end
	 max = hi
	 cumulative = cumulative + (lo + hi) / 2 * tonumber(count)
      end
   end
   local avg = cumulative / tonumber(total)
   return min * 1e6, avg * 1e6, max * 1e6
end

local leaf_mt = {}
local function make_leaf(value, rrd)
   return setmetatable({value=value, rrd=rrd}, leaf_mt)
end
local function is_leaf(x) return getmetatable(x) == leaf_mt end

local function compute_histograms_tree(histograms)
   if histograms == nil then return {} end
   local ret = {}
   for k,v in pairs(histograms) do
      local branches, leaf = dirsplit(k)
      local parent = ret
      for branch in branches:split('/') do
         if parent[branch] == nil then parent[branch] = {} end
         parent = parent[branch]
      end
      parent[leaf] = make_leaf(function() return v:snapshot() end)
   end
   return ret
end

local function compute_counters_tree(counters, rrds)
   if counters == nil then return {} end
   local ret = {}
   for k,v in pairs(counters) do
      local branches, leaf = dirsplit(k)
      if leaf ~= 'dtime' then
         local parent = ret
         for branch in branches:split('/') do
            if parent[branch] == nil then parent[branch] = {} end
            parent = parent[branch]
         end
         parent[leaf] = make_leaf(
            function() return counter.read(v) end, rrds[k])
      end
   end
   -- The rxpackets and rxbytes link counters are redundant.
   if ret.links then
      local links = {}
      for link, counters in pairs(ret.links) do
         links[link] = { txpackets=counters.txpackets,
                         txbytes=counters.txbytes,
                         txdrop=counters.txdrop }
      end
      ret.links = links
   end
   return ret
end

local function adjoin(t, k, v)
   if t[k] == nil then t[k] = v; return end
   if t[k] == v then return end
   assert(type(t[k]) == 'table' and not is_leaf(t[k]))
   assert(type(v) == 'table' and not is_leaf(v))
   for vk, vv in pairs(v) do adjoin(t[k], vk, vv) end
end

-- Return a tree that presents the set of Snabb instances in a tree,
-- where workers are nested inside their parents, and the counters and
-- histograms are part of that tree as well.
local function compute_tree()
   local parents = {}
   for pid, instance in pairs(snabb_state.instances) do
      parents[pid] = instance.group or pid
   end
   local root = {}
   for pid,parent_pid in pairs(parents) do
      local parent_instance = snabb_state.instances[parent_pid]
      local parent_name = (parent_instance and parent_instance.name) or tostring(parent_pid)
      if root[parent_name] == nil then root[parent_name] = {} end
      local parent_node = root[parent_name]
      local node
      if parent_pid == pid then
         node = parent_node
      else
         node = {}
         if parent_node.workers == nil then parent_node.workers = {} end
         parent_node.workers[pid] = node
      end
      node.pid = pid
      for k,v in pairs(compute_histograms_tree(snabb_state.histograms[pid])) do
         adjoin(node, k, v)
      end
         for k,v in pairs(compute_counters_tree(snabb_state.counters[pid],
                                                snabb_state.rrds[pid] or {})) do
         adjoin(node, k, v)
      end
   end
   return root
end

local function nil_if_empty(x)
   for k,v in pairs(x) do return x end
   return nil
end

-- The ui.tree just represents the structure of the state.  Before we go
-- to show that state, we need to sample the associated values (the
-- counters and histograms).  Additionally at this point we'll prune out
-- data that the user doesn't want to see.
local function sample_tree(tree)
   local ret = {}
   for k,v in pairs(tree) do
      if is_leaf(v) then v = make_leaf(v.value(), v.rrd)
      elseif type(v) == 'table' then v = sample_tree(v) end
      ret[k] = v
   end
   return nil_if_empty(ret)
end

local function prune_sample(tree)
   local function prune(name, tree)
      if name == 'apps' and not ui.show_apps then return nil end
      if name == 'links' and not ui.show_links then return nil end
      if name == 'engine' and not ui.show_engine then return nil end
      if is_leaf(tree) then
         if not ui.show_empty and tonumber(tree.value) == 0 then return nil end
      elseif type(tree) == 'table' then
         local ret = {}
         for k,v in pairs(tree) do ret[k] = prune(k, v) end
         return nil_if_empty(ret)
      end
      return tree
   end
   local function prune_instance(instance)
      local ret = {}
      if instance.workers then
         ret.workers = {}
         for k,v in pairs(instance.workers) do
            ret.workers[k] = prune_instance(v)
         end
         ret.workers = nil_if_empty(ret.workers)
      end
      if ui.focus == nil or ui.focus == instance.pid then
         for k,v in pairs(instance) do
            if k ~= 'workers' then ret[k] = prune(k, v) end
         end
      end
      return nil_if_empty(ret)
   end
   local ret = {}
   for k,v in pairs(tree) do ret[k] = prune_instance(v) end
   return ret
end

local function compute_rate(v, prev, rrd, t, dt)
   if ui.pause_time and t ~= ui.pause_time then
      if not rrd then return 0 end
      for name,source in pairs(rrd:ref(ui.pause_time)) do
         for _,reading in ipairs(source.cf.average) do
            return reading.value
         end
      end
      return 0/0
   elseif prev then
      return tonumber(v - prev)/dt
   else
      return 0/0
   end
end

local function scale(x)
   x=tonumber(x)
   for _,scale in ipairs {{'T', 1e12}, {'G', 1e9}, {'M', 1e6}, {'k', 1e3}} do
      local tag, base = unpack(scale)
      if x > base then return x/base, tag end
   end
   return x, ''
end

local compute_display_tree = {}

local macaddr_string
do
   local buf = ffi.new('union { uint64_t u64; uint8_t bytes[6]; }')
   function macaddr_string(n)
      -- The app read out the address and wrote it to the counter as a
      -- uint64, just as if it aliased the address.  So, to get the
      -- right byte sequence, we can do the same, without swapping.
      buf.u64 = n
      return ethernet:ntop(buf.bytes)
   end
end

-- The state renders to a nested display tree, consisting of "group",
-- "rows", "grid", and "chars" elements.
function compute_display_tree.tree(tree, prev, dt, t)
   local function chars(align, fmt, ...)
      return {kind='chars', align=align, contents=fmt:format(...)}
   end
   local function lchars(fmt, ...) return chars('left', fmt, ...) end
   tree = prune_sample(tree)
   local function visit(tree, prev)
      local ret = {kind='rows', contents={}}
      for k, v in sortedpairs(tree) do
         local prev = prev and prev[k]
         local rrd
         if is_leaf(v) then
            v, rrd = v.value, v.rrd
            if is_leaf(prev) then prev = prev.value else prev = nil end
         elseif type(v) ~= type(prev) then
            prev = nil
         end
         if type(v) ~= 'table' then
            local out
            if type(v) == 'cdata' and tonumber(v) then
               local units
               if k:match('packets') then units = 'PPS'
               elseif k:match('bytes') then units = 'bytes/s'
               elseif k:match('bits') then units = 'bps'
               elseif k:match('breath') then units = 'breaths/s'
               elseif k:match('drop') then units = 'PPS'
               end
               local show_rates = units or tonumber(v) ~= tonumber(prev)
               show_rates = show_rates and ui.show_rates
               show_rates = show_rates or (ui.pause_time and ui.pause_time ~= t)
               if show_rates then
                  local rate = compute_rate(v, prev, rrd, t, dt)
                  local v, tag = scale(rate)
                  out = lchars("%s: %.3f %s%s", k, v, tag, units or "/sec")
               elseif k:match('macaddr') then
                  out = lchars("%s: %s", k, macaddr_string(v))
               else
                  out = lchars("%s: %s", k, lib.comma_value(v))
               end
            elseif type(v) == 'cdata' then
               -- Hackily, assume that the value is a histogram.
               out = lchars('%s: %.2f min, %.2f avg, %.2f max',
                            k, summarize_histogram(v, prev))
            else
               out = lchars("%s: %s", k, tostring(v))
            end
            table.insert(ret.contents, out)
         end
      end
      for k, v in sortedpairs(tree) do
         if type(v) == 'table' and not is_leaf(v) then
            local has_prev = prev and type(prev[k]) == type(v)
            local rows = visit(v, has_prev and prev[k])
            table.insert(ret.contents, {kind='group', label=k, contents=rows})
         end
      end
      return ret
   end
   return {kind='rows',
           contents={lchars('snabb top: %s',
                            os.date('%Y-%m-%d %H:%M:%S', ui.pause_time or t)),
                     lchars('----'),
                     visit(tree, prev)}}
end

function compute_display_tree.interface(tree, prev, dt, t)
   local function chars(align, fmt, ...)
      return {kind='chars', align=align, contents=fmt:format(...)}
   end
   local function lchars(fmt, ...) return chars('left', fmt, ...) end
   local function cchars(fmt, ...) return chars('center', fmt, ...) end
   local function rchars(fmt, ...) return chars('right', fmt, ...) end
   local grid = {}
   local rows = {
      kind='rows',
      contents = {
         lchars('snabb top: %s',
                os.date('%Y-%m-%d %H:%M:%S', ui.pause_time or t)),
         lchars('----'),
         {kind='grid', width=6, shrink={true,true}, contents=grid}
   }}
   local function gridrow(...) table.insert(grid, {...}) end
   --  name or \---, pid, breaths/s, latency
   --            \-  pci device, macaddr, mtu, speed
   --                  RX:       PPS, bps, %, [drops/s]
   --                  TX:       PPS, bps, %, [drops/s]
   function queue_local_key(key, counters)
      local queue_key
      local stem = ({rxdrop='rxdrops'})[key] or key
      for i=0,15 do
         local k = 'q'..i..'_'..stem
         if counters[k] then
            if queue_key then
               return key
            end
            queue_key = k
         end
      end
      return queue_key or key
   end
   local function rate(key, counters, prev)
      if not counters then return 0/0 end
      if not counters[key] then return 0/0 end
      key = queue_local_key(key, counters)
      local v, rrd = counters[key], nil
      prev = prev and prev[key]
      if is_leaf(v) then
         v, rrd, prev = v.value, v.rrd, is_leaf(prev) and prev.value or nil
      end
      return compute_rate(v, prev, rrd, t, dt)
   end
   local function show_traffic(tag, pci, prev)
      local pps = rate(tag..'packets', pci, prev)
      local bytes = rate(tag..'bytes', pci, prev)
      local drops = rate(tag..'drop', pci, prev)
      -- 7 bytes preamble, 1 start-of-frame, 4 CRC, 12 interframe gap.
      local overhead = (7 + 1 + 4 + 12) * pps
      local bps = (bytes + overhead) * 8
      local max = tonumber(pci.speed and pci.speed.value) or 0
      gridrow(nil,
              rchars('%s:', tag:upper()),
              lchars('%.3f %sPPS', scale(pps)),
              lchars('%.3f %sbps', scale(bps)),
              max > 0 and lchars('%.2f%%', bps/max*100) or nil,
              drops > 0 and rchars('%.3f %sPPS dropped', scale(drops)) or nil)
   end
   local function show_pci(addr, pci, prev)
      local bps, tag = scale(tonumber(pci.speed and pci.speed.value) or 0)
      gridrow(rchars('| '), lchars(''))
      gridrow(rchars('\\-'),
              rchars('%s:', addr),
              lchars('%sMAC: %s',
                     (bps > 0 and ("%d %sbE, "):format(bps, tag)) or '',
                     macaddr_string(tonumber(pci.macaddr and pci.macaddr.value) or 0)))
      show_traffic('rx', pci, prev)
      show_traffic('tx', pci, prev)
   end
   local function union(dst, src)
      if type(src) == 'table' and not is_leaf(src) then
         for k, v in pairs(src) do
            if dst[k] == nil then
               dst[k] = v
            elseif not is_leaf(v) and not is_leaf(dst[k]) then
               union(dst[k], v)
            end
         end
      end
   end
   local function find_pci_devices(node, ret)
      ret = ret or {}
      if type(node) == 'table' and not is_leaf(node) then
         for k, v in pairs(node) do
            if k == 'pci' then
               union(ret, v)
            else
               find_pci_devices(v, ret)
            end
         end
      end
      return ret
   end
   local function show_instance(label, instance, prev)
      local pci, prev_pci = find_pci_devices(instance), find_pci_devices(prev)
      local engine, prev_engine = instance.engine, prev and prev.engine
      local latency = engine and engine.latency and engine.latency.value
      local latency_str = ''
      if latency then 
         local prev = prev_engine and prev_engine.latency and prev_engine.latency.value
         latency_str = string.format('latency: %.2f min, %.2f avg, %.2f max',
                                     summarize_histogram(latency, prev))
      end
      gridrow(label,
              lchars('PID %s:', instance.pid),
              lchars('%.2f %sbreaths/s',
                     scale(rate('breaths', engine, prev_engine))),
              lchars('%s', latency_str))
      if instance.workers then
         for pid, instance in sortedpairs(instance.workers) do
            local prev = prev and prev.workers and prev.workers[pid]
            gridrow(rchars('|   '), lchars(''))
            show_instance(rchars('\\---'), instance, prev)
         end
      else
         -- Note, PCI tree only shown on instances without workers.
         for addr, pci in sortedpairs(pci) do
            show_pci(addr, pci, prev_pci[addr])
         end
      end
   end
   for name, instance in sortedpairs(tree) do
      gridrow(lchars(''))
      show_instance(lchars('%s', name), instance, prev and prev[name])
   end
   return rows
end

local function compute_span(row, j, columns)
   local span = 1
   while j + span <= columns and row[j+1] == nil do
      span = span + 1
   end
   return span
end

-- A tree is nice for data but we have so many counters that really we
-- need to present them as a grid.  So, the next few functions try to
-- reorient "rows" display tree instances into "grid".
local function compute_min_width(tree)
   if tree.kind == 'group' then
      return 2 + compute_min_width(tree.contents)
   elseif tree.kind == 'rows' then
      local width = 0
      for _,tree in ipairs(tree.contents) do
         width = math.max(width, compute_min_width(tree))
      end
      return width
   elseif tree.kind == 'grid' then
      local columns, width = tree.width, 0
      for j=1,columns do
         local col_width = 0
         for i=1,#tree.contents do
            local row = tree.contents[i]
            local tree = row[j]
            if tree then
               local span = compute_span(row, j, columns)
               local item_width = compute_min_width(tree)
               col_width = math.max(col_width, math.ceil(item_width / span))
            end
         end
         width = width + col_width
      end
      return width
   else
      assert(tree.kind == 'chars')
      return #tree.contents
   end
end

local function compute_height(tree)
   if tree.kind == 'group' then
      return 1 + compute_height(tree.contents)
   elseif tree.kind == 'rows' then
      local height = 0
      for _,tree in ipairs(tree.contents) do
         height = height + compute_height(tree)
      end
      return height
   elseif tree.kind == 'grid' then
      local height = 0
      for i=1,#tree.contents do
         local row_height = 0
         for j=1,tree.width do
            local tree = tree.contents[i][j]
            row_height = math.max(row_height, compute_height(tree))
         end
         height = height + row_height
      end
      return height
   else
      assert(tree.kind == 'chars')
      return 1
   end
end

local function has_compatible_height(tree, height)
   if height <= 0 then
      return false
   elseif tree.kind == 'group' then
      return has_compatible_height(tree.contents, height - 1)
   elseif tree.kind == 'rows' then
      for _,tree in ipairs(tree.contents) do
         height = height - compute_height(tree)
         if height <= 0 then return false end
      end
      return height <= 2
   elseif tree.kind == 'chars' then
      return height <= 2
   else
      return false
   end
end

local function should_make_grid(tree, indent)
   if #tree.contents <= 1 then return 1 end
   local width = compute_min_width(tree) + indent
   -- Maximum column width of 80.
   if width > 80 then return 1 end
   -- Minimum column width of 50.
   width = math.max(width, 50)
   local count = math.floor(ui.cols / width)
   if count < 2 then return 1 end
   -- Only make a grid out of similar rows.
   local contents = tree.contents
   local kind, height = contents[1].kind, compute_height(contents[1])
   for i=2,#contents do
      if contents[i].kind ~= kind then return 1 end
      if not has_compatible_height(contents[i], height) then return 1 end
   end
   return count -- math.min(count, #contents)
end

local function create_grids(tree, indent)
   indent = indent or 0
   if tree.kind == 'rows' then
      local columns = should_make_grid(tree, indent)
      if columns > 1 then
         local rows = math.ceil(#tree.contents/columns)
         local contents = {}
         for i=1,rows do
            contents[i] = {}
         end
         for i,tree in ipairs(tree.contents) do
            local row, col = ((i-1)%rows)+1, math.ceil(i/rows)
            contents[row][col] = tree
         end
         return {kind='grid', width=columns, contents=contents}
      else
         local contents = {}
         for i,tree in ipairs(tree.contents) do
            contents[i] = create_grids(tree, indent)
         end
         return {kind='rows', contents=contents}
      end
   elseif tree.kind == 'group' then
      return {kind='group', label=tree.label,
              contents=create_grids(tree.contents, indent + 2)}
   else return tree end
end

-- Finally, here we render the display tree to the screen.  Our code
-- always renders a full screen, even when only part of the state
-- changes.  We could make that more efficient in the future.
local render = {}
local function render_display_tree(tree, row, col, width)
   if row >= ui.rows then
      local msg = '[truncated]'
      move(ui.rows-1, ui.cols - #msg)
      io.write(msg)
      return row
   else
      return assert(render[tree.kind])(tree, row, col, width)
   end
end

function render.group(tree, row, col, width)
   move(row, col)
   printf("%s:", tree.label)
   return render_display_tree(tree.contents, row + 1, col + 2, width - 2)
end
function render.rows(tree, row, col, width)
   move(row, col)
   for _,tree in ipairs(tree.contents) do
      row = render_display_tree(tree, row, col, width)
   end
   return row
end
local function allocate_column_widths(rows, cols, shrink, width)
   local widths, expand, total = {}, 0, 0
   for j=1,cols do
      local col_width = 0
      for _,row in ipairs(rows) do
         if row[j] then
            local span = compute_span(row, j, cols)
            local item_width = compute_min_width(row[j])
            col_width = math.max(col_width, math.ceil(item_width / span))
         end
      end
      widths[j], total = col_width, total + col_width
      if not shrink[j] then expand = expand + 1 end
   end
   -- Truncate from the right.
   for j=1,cols do
      -- Inter-column spacing before this column.
      local spacing = j - 1
      if total + spacing <= width then break end
      local trim = math.min(widths[j], total + spacing - width)
      widths[j], total = widths[j] - trim, total - trim
   end
   -- Allocate slack to non-shrinking columns.
   for j=1,cols do
      if not shrink[j] then
         local spacing = j - 1
         local pad = math.floor((width-total-spacing)/expand)
         widths[j], total, expand = widths[j] + pad, total + pad, expand - 1
      end
   end
   return widths
end
function render.grid(tree, row, col, width)
   local widths = allocate_column_widths(
      tree.contents, tree.width, tree.shrink or {}, width)
   for i=1,#tree.contents do
      local next_row = row
      local endcol = col + width
      local col = endcol
      for j=tree.width,1,-1 do
         local tree = tree.contents[i][j]
         col = col - widths[j]
         if tree then
            local width = endcol - col
            next_row = math.max(
               next_row, render_display_tree(tree, row, col, endcol - col))
            -- Spacing.
            endcol = col - 1
         end
         -- Spacing.
         col = col - 1
      end
      row = next_row
   end
   return row
end
function render.chars(tree, row, col, width)
   local str = tree.contents
   if #str > width then
      move(row, col)
      io.write(str:sub(1,width))
   else
      local advance = 0
      if tree.align=='right' then advance = width - #str
      elseif tree.align=='center' then advance = math.floor((width - #str)/2)
      else advance = 0 end
      move(row, col + advance)
      io.write(tree.contents)
   end
   return row + 1
end

-- The status line tells the user what keys are available, and also
-- tells them what the current state is (e.g. apps hidden).
local function render_status_line()
   local function showhide(key, what)
      if ui['show_'..what] then return key..'=hide '..what end
      return key..'=show '..what
   end
   local entries = {}
   table.insert(entries, 'q=quit')
   if ui.pause_time then
      table.insert(entries, 'SPACE=unpause')
      table.insert(entries, '[=rewind 1s')
      table.insert(entries, ']=advance 1s')
      table.insert(entries, '{=rewind 60s')
      table.insert(entries, '}=advance 60s')
   else
      table.insert(entries, 'SPACE=pause')
   end
   if ui.view == 'interface' then
      table.insert(entries, 't=tree view')
   else
      for _,e in ipairs { 'i=interface view', showhide('a', 'apps'),
                          showhide('l', 'links'), showhide('e', 'engine'),
                          showhide('0', 'empty'), showhide('r', 'rates') } do
         table.insert(entries, e)
      end
      local instances = 0
      for pid, _ in sortedpairs(snabb_state.instances) do
         instances = instances + 1
      end
      if instances > 1 then
         if ui.focus then table.insert(entries, 'u=unfocus '..ui.focus) end
         table.insert(entries, '<=focus prev')
         table.insert(entries, '>=focus next')
      end
   end

   local col_width, count = 0, 0
   for i,entry in ipairs(entries) do
      local width = math.max(col_width, #entry + 2)
      if width * (count + 1) <= ui.cols then
         col_width, count = width, count + 1
      else
         break
      end
   end
   for i=1,count do
      move(ui.rows, 1 + (i-1)*col_width)
      io.write(entries[i])
   end
end

local function refresh()
   move(1,1)
   clearterm()
   local dt
   if ui.prev_sample_time then dt = ui.sample_time - ui.prev_sample_time end
   local tree = compute_display_tree[ui.view](
      ui.sample, ui.prev_sample, dt, ui.sample_time)
   tree = create_grids(tree)
   render_display_tree(tree, 1, 1, ui.cols)
   render_status_line()
   io.flush()
end

local function show_ui()
   request_dimensions()
   fiber.spawn(monitor_sigwinch)
   while true do
      local s = snabb_state
      if ui.tree == nil then
         ui.tree = compute_tree() or {}
         ui.prev_sample, ui.prev_sample_time = nil, nil
      end
      if not ui.pause_time then
         ui.prev_sample_time, ui.prev_sample = ui.sample_time, ui.sample
         ui.sample_time, ui.sample = rrd.now(), sample_tree(ui.tree) or {}
      end
      refresh()
      ui.wake:wait()
      ui.wake = cond.new()
      -- Limit UI refresh rate to 40 Hz.
      if ui.interactive then sleep.sleep(0.025) end
   end
end

-- Tell the display to refresh every second.
local function refresh_display()
   while true do
      sleep.sleep(1)
      needs_redisplay(true)
   end
end

-- Here we wire up some more key bindings.
local function in_view(view, f)
   return function() if ui.view == view then f() end end
end

local function toggle(tab, k)
   return function() tab[k] = not tab[k]; needs_redisplay(true) end
end

local function sortedkeys(t)
   local ret = {}
   for k,v in sortedpairs(t) do table.insert(ret, k) end
   return ret
end
local function focus_prev()
   local pids = sortedkeys(snabb_state.instances)
   if #pids < 2 then return end
   if ui.focus == nil or ui.focus == pids[1] then
      ui.focus = pids[#pids]
   else
      for i,pid in ipairs(pids) do
         if pid == ui.focus then
            ui.focus = pids[i-1]
            break
         end
      end
   end
   needs_redisplay(true)
end

local function focus_next()
   local pids = sortedkeys(snabb_state.instances)
   if #pids < 2 then return end
   if ui.focus == nil or ui.focus == pids[#pids] then
      ui.focus = pids[1]
   else
      for i,pid in ipairs(pids) do
         if pid == ui.focus then
            ui.focus = pids[i+1]
            break
         end
      end
   end
   needs_redisplay(true)
end

local function unfocus()
   ui.focus = nil
   needs_redisplay(true)
end

local function tree_view()
   ui.view = 'tree'
   needs_redisplay(true)
end

local function interface_view()
   ui.view = 'interface'
   needs_redisplay(true)
end

local function toggle_paused()
   if ui.pause_time then
      ui.pause_time = nil
   else
      ui.pause_time = ui.sample_time or rrd.now()
   end
   needs_redisplay(true)
end

local function rewind(secs)
   return function()
      if not ui.sample_time then return end -- Ensure we have a sample.
      if not ui.pause_time then return end -- Only work when paused.
      ui.pause_time = ui.pause_time - secs
      needs_redisplay(true)
   end
end

bind_keys("0", in_view('tree', toggle(ui, 'show_empty')))
bind_keys("r", in_view('tree', toggle(ui, 'show_rates')))
bind_keys("l", in_view('tree', toggle(ui, 'show_links')))
bind_keys("a", in_view('tree', toggle(ui, 'show_apps')))
bind_keys("e", in_view('tree', toggle(ui, 'show_engine')))
bind_keys(" ", toggle_paused)
bind_keys("u", in_view('tree', unfocus))
bind_keys("t", in_view('interface', tree_view))
bind_keys("i", in_view('tree', interface_view))
bind_keys("[", rewind(1))
bind_keys("]", rewind(-1))
bind_keys("{", rewind(60))
bind_keys("}", rewind(-60))
bind_keys("<", in_view('tree', focus_prev))
bind_keys(">", in_view('tree', focus_next))
bind_keys("AD", global_key_bindings['<'], csi_key_bindings) -- Left and up arrow.
bind_keys("BC", global_key_bindings['>'], csi_key_bindings) -- Right and down arrow.
bind_keys("q\3\31\4", fiber.stop) -- C-d, C-/, q, and C-c.

local function handle_input ()
   for c in io.stdin.read_char, io.stdin do
      global_key_bindings[c](c)
   end
   fiber.stop()
end

-- Finally, here's the code!
function run (args)
   local opt = {}
   function opt.h (arg) print(usage) main.exit(1) end
   args = lib.dogetopt(args, opt, "h", {help='h'})

   if #args ~= 0 then print(usage) main.exit(1) end

   require('lib.fibers.file').install_poll_io_handler()
   require('lib.stream.compat').install()

   ui.interactive = S.stdin:isatty() and S.stdout:isatty()
   if ui.interactive then
      ui.saved_tc = assert(S.tcgetattr(S.stdin))
      local new_tc = makeraw(ui.saved_tc)
      assert(S.tcsetattr(S.stdin, 'drain', new_tc))
      scroll(1000)
   end

   fiber.spawn(update_snabb_state)
   fiber.spawn(handle_input)
   fiber.spawn(show_ui)

   if ui.interactive then
      fiber.spawn(refresh_display)
      fiber.main()
      assert(S.tcsetattr(S.stdin, 'drain', ui.saved_tc))
      bgcolordefault()
      fgcolordefault()
      io.stdout:write_chars('\n')
   else
      -- FIXME: This doesn't work currently.
      local sched = fiber.current_scheduler
      while #sched.next > 0 do
         sched:run()
         sched:schedule_tasks_from_sources()
      end
   end
end
