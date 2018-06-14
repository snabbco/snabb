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
   tree=nil, focus=nil, wake=cond.new(), rows=24, cols=80,
   show_empty=false, show_rates=true,
   show_links=true, show_apps=true, show_engine=true,
   paused=false }

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
               if pid and is_dir(event.name) and not by_pid[pid] then
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
   fiber.spawn(function ()
      for event in rx.get, rx do
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
      parent[leaf] = function() return v:snapshot() end
   end
   return ret
end

local function compute_counters_tree(counters)
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
         parent[leaf] = function() return counter.read(v) end
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
   assert(type(t[k]) == 'table')
   assert(type(v) == 'table')
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
      if ui.focus == nil or ui.focus == pid then
         for k,v in pairs(compute_histograms_tree(snabb_state.histograms[pid])) do
            adjoin(node, k, v)
         end
         for k,v in pairs(compute_counters_tree(snabb_state.counters[pid])) do
            adjoin(node, k, v)
         end
      end
   end
   return root
end

local function isempty(x)
   for k,v in pairs(x) do return false end
   return true
end

local function maybe_hide(tab, ...)
   for _,k in ipairs{...} do
      if tab[k] and not ui['show_'..k] then tab[k] = nil end
   end
end

-- The ui.tree just represents the structure of the state.  Before we go
-- to show that state, we need to sample the associated values (the
-- counters and histograms).  Additionally at this point we'll prune out
-- data that the user doesn't want to see.
local function sample_tree(tree)
   local ret = {}
   for k,v in pairs(tree) do
      if type(v) == 'function' then v = v() end
      if type(v) == 'table' then ret[k] = sample_tree(v)
      elseif not ui.show_empty and tonumber(v) == 0 then
         -- Pass.
      else
         ret[k] = v
      end
   end
   maybe_hide(ret, 'apps', 'links', 'engine')
   if isempty(ret) then return end
   return ret
end

-- The state renders to a nested display tree, consisting of "group",
-- "rows", "columns", and "chars" elements.
local function compute_display_tree(tree, prev, dt)
   local ret = {kind='rows', contents={}}
   for k, v in sortedpairs(tree) do
      if type(v) ~= 'table' then
         local prev = prev and type(prev[k]) == type(v) and prev[k]
         if type(v) == 'cdata' and tonumber(v) then
            if ui.show_rates and prev and tonumber(v) ~= tonumber(prev) then
               if k:match('packets') then units = 'PPS'
               elseif k:match('bytes') then units = 'bytes/s'
               elseif k:match('bits') then units = 'bits/s'
               else units = 'per second' end
               local rate = math.floor(tonumber(v-prev)/dt)
               str = string.format("%s: %s %s", k, lib.comma_value(rate), units)
            else
               str = string.format("%s: %s", k, lib.comma_value(v))
            end
         elseif type(v) == 'cdata' then
            -- Hackily, assume that the value is a histogram.
            str = string.format('%s: %.2f min, %.2f avg, %.2f max',
                                k, summarize_histogram(v, prev))
         else
            str = string.format("%s: %s", k, tostring(v))
         end
         table.insert(ret.contents, {kind='chars', contents=str})
      end
   end
   for k, v in sortedpairs(tree) do
      if type(v) == 'table' then
         local has_prev = prev and type(prev[k]) == type(v)
         local rows = compute_display_tree(v, has_prev and prev[k], dt)
         table.insert(ret.contents, {kind='group', label=k, contents=rows})
      end
   end
   return ret
end

-- A tree is nice for data but we have so many counters that really we
-- need to present them as a grid.  So, the next few functions try to
-- reorient "rows" display tree instances into a combination of "rows"
-- and "columns".
local function compute_width(tree)
   if tree.kind == 'group' then
      return 2 + compute_width(tree.contents)
   elseif tree.kind == 'rows' then
      local width = 0
      for _,tree in ipairs(tree.contents) do
         width = math.max(width, compute_width(tree))
      end
      return width
   elseif tree.kind == 'columns' then
      local width = 0
      for _,tree in ipairs(tree.contents) do
         width = math.max(width, compute_width(tree))
      end
      return width * tree.width
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
   elseif tree.kind == 'columns' then
      local height = 0
      for _,tree in ipairs(tree.contents) do
         height = math.max(height, compute_height(tree))
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
   local width = compute_width(tree) + indent
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
            contents[i] = {kind='columns', width=columns, contents={}}
         end
         for i,tree in ipairs(tree.contents) do
            local row, col = ((i-1)%rows)+1, math.ceil(i/rows)
            contents[row].contents[col] = tree
         end
         if rows == 1 then return contents[1] end
         return {kind='rows', contents=contents}
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
function render.columns(tree, row, col, width)
   local width = math.floor(width / tree.width)
   local next_row = row
   for i,tree in ipairs(tree.contents) do
      next_row = math.max(next_row, render_display_tree(tree, row, col, width))
      col = col + width
   end
   return next_row
end
function render.chars(tree, row, col, width)
   move(row, col)
   if #tree.contents > width then
      io.write(tree.contents:sub(1,width))
   else
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
   local entries = { ui.paused and 'SPACE=unpause' or 'SPACE=pause',
                     'q=quit',
                     showhide('a', 'apps'), showhide('l', 'links'),
                     showhide('e', 'engine'), showhide('0', 'empty'),
                     showhide('r', 'rates') }
   local instances = 0
   for pid, _ in sortedpairs(snabb_state.instances) do
      instances = instances + 1
   end
   if instances > 1 then
      if ui.focus then table.insert(entries, 'u=unfocus '..ui.focus) end
      table.insert(entries, '<=focus prev')
      table.insert(entries, '>=focus next')
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
   local tree = compute_display_tree(ui.sample, ui.prev_sample, dt)
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
      if not ui.paused then
         ui.prev_sample_time, ui.prev_sample = ui.sample_time, ui.sample
         ui.sample_time, ui.sample = C.get_monotonic_time(), sample_tree(ui.tree) or {}
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
local function toggle(tab, k)
   return function() tab[k] = not tab[k]; needs_redisplay(true) end
end

local function unfocus()
   ui.focus = nil
   needs_redisplay(true)
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
   needs_redisplay()
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
   needs_redisplay()
end

local function unfocus()
   ui.focus = nil
   needs_redisplay()
end

bind_keys("0", toggle(ui, 'show_empty'))
bind_keys("r", toggle(ui, 'show_rates'))
bind_keys("l", toggle(ui, 'show_links'))
bind_keys("a", toggle(ui, 'show_apps'))
bind_keys("e", toggle(ui, 'show_engine'))
bind_keys(" ", toggle(ui, 'paused'))
bind_keys("u", unfocus)
bind_keys("<", focus_prev)
bind_keys(">", focus_next)
bind_keys("AD", focus_prev, csi_key_bindings) -- Left and up arrow.
bind_keys("BC", focus_next, csi_key_bindings) -- Right and down arrow.
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
