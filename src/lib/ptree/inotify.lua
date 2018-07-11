-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local ffi     = require("ffi")
local S       = require("syscall")
local lib     = require("core.lib")
local file    = require("lib.stream.file")
local fiber   = require("lib.fibers.fiber")
local file_op = require("lib.fibers.file")
local op      = require("lib.fibers.op")
local channel = require("lib.fibers.channel")
local cond    = require("lib.fibers.cond")
local sleep   = require("lib.fibers.sleep")

-- Fixed-size part of an inotify event.
local inotify_event_header_t = ffi.typeof[[
struct {
   int      wd;       /* Watch descriptor */
   uint32_t mask;     /* Mask describing event */
   uint32_t cookie;   /* Unique cookie associating related
                         events (for rename(2)) */
   uint32_t len;      /* Size of name field */
   // char  name[];   /* Optional null-terminated name */
}]]

local function event_has_flags(event, flags)
   return bit.band(event.mask, S.c.IN[flags]) ~= 0
end

local function warn(msg, ...)
   io.stderr:write(string.format(msg.."\n", ...))
end

local function open_inotify_stream(name, events)
   local fd = assert(S.inotify_init("cloexec, nonblock"))
   assert(fd:inotify_add_watch(name, events))
   return file.fdopen(fd, "rdonly")
end

-- Return a channel on which to receive inotify events.  Takes as an
-- argument an operation that, if performable, will shut down the
-- channel.
function inotify_event_channel(file_name, events, cancel_op)
   local stream = open_inotify_stream(file_name, events)
   local ch = channel.new()
   if cancel_op ~= nil then
      cancel_op = cancel_op:wrap(function () return 'cancelled' end)
   end
   local select_op = op.choice(file_op.stream_readable_op(stream),
                               cancel_op)
   fiber.spawn(function ()
      while select_op:perform() ~= 'cancelled' do
         local ev = stream:read_struct(nil, inotify_event_header_t)
         local name
         if ev.len ~= 0 then
            local buf = ffi.new('uint8_t[?]', ev.len)
            stream:read_bytes_or_error(buf, ev.len)
            name = ffi.string(buf)
         end
         ch:put({wd=ev.wd, mask=ev.mask, cookie=ev.cookie, name=name})
      end
      stream:close()
      ch:put(nil)
   end)
   return ch
end

-- The number of inotify watches is limited on a system-wide basis, in
-- addition to the limit in number of open file descriptors.  Hence we
-- have this fallback, should we fail to open inotify.
local function fallback_directory_events(dir, cancel_op)
   local ch = channel.new()
   if cancel_op ~= nil then
      cancel_op = cancel_op:wrap(function () return 'cancelled' end)
   end
   local select_op = op.choice(sleep.sleep_op(1), cancel_op)
   local inventory = {}
   fiber.spawn(function ()
      local size = 4096
      local buf = S.t.buffer(4096)
      local now = 0
      while select_op:perform() ~= 'cancelled' do
         local iter, err = S.util.ls(dir, buf, size)
         if not iter then break end
         now = now + 1
         for f in iter do
            if f ~= '.' and f ~= '..' then
               if not inventory[f] then
                  ch:put({mask=S.c.IN.create, name=f})
               end
               inventory[f] = now
            end
         end
         for f,t in pairs(inventory) do
            if t < now then
               inventory[f] = nil
               ch:put({mask=S.c.IN.delete, name=f})
            end
         end
      end
      ch:put(nil)
   end)
   return ch
end

-- Return a channel on which to receive events like {kind=add,
-- name=NAME} or {kind=remove, name=NAME}.  Will begin by emitting an
-- "mkdir" event for the directory being monitored, then "add" events
-- for each if its members.  If the directory is moved or deleted, or
-- the stream is cancelled via cancel_op, the stream will be terminated,
-- releasing its resources, issuing "remove" events for all members
-- before issuing a final "mkdir" event for the directory itself,
-- followed by a tombstone of nil.
function directory_inventory_events(dir, cancel_op)
   local events = "create,delete,moved_to,moved_from,move_self,delete_self"
   local watch_flags = "onlydir"
   local flags = events..','..watch_flags
   local cancel = cond.new()
   cancel_op = op.choice(cancel:wait_operation(), cancel_op)
   local inotify_ok, rx = pcall(inotify_event_channel, dir, flags, cancel_op)
   if not inotify_ok then
      rx = fallback_directory_events(dir, cancel_op)
   end
   local tx = channel.new()
   local inventory = {}
   for _,name in ipairs(S.util.dirtable(dir) or {}) do
      if name ~= "." and name ~= ".." then inventory[dir..'/'..name] = true end
   end

   fiber.spawn(function ()
      tx:put({kind="mkdir", name=dir})
      for name,_ in pairs(inventory) do tx:put({kind="add", name=name}) end
      for event in rx.get, rx do
         if event_has_flags(event, "delete,moved_from") then
            local name = dir..'/'..event.name
            if inventory[name] then tx:put({kind="remove", name=name}) end
            inventory[name] = nil
         end
         if event_has_flags(event, "create,moved_to") then
            local name = dir..'/'..event.name
            if not inventory[name] then tx:put({kind="add", name=name}) end
            inventory[name] = true
         end
         if event_has_flags(event, "move_self,delete_self") then
            cancel:signal()
         end
      end
      for name,_ in pairs(inventory) do
         tx:put({kind="remove", name=name})
      end
      tx:put({kind="rmdir", name=dir})
      tx:put(nil)
   end)
   return tx
end

local function is_dir(name)
   local stat = S.lstat(name)
   return stat and stat.isdir
end

-- Return a channel on which to receive events like {kind=KIND,
-- name=NAME} for the KIND in {mkdir, rmdir, creat, rm}.  The former two
-- are for directories and the latter for files.  Will begin by emitting
-- an "mkdir" event for the directory being monitored.  If the directory
-- is moved or deleted, or the stream is cancelled via cancel_op, the
-- stream will be terminated, releasing its resources, issuing rm/rmdir
-- events for all members before issuing a final rmdir event for the
-- directory itself, followed by a tombstone of nil.
function recursive_directory_inventory_events(dir, cancel_op)
   local tx = channel.new()
   local rx = directory_inventory_events(dir, cancel_op)

   fiber.spawn(function ()
      -- name -> {ch,cancel}
      local subdirs = {}
      local function recompute_rx_op()
         local ops = {rx:get_operation()}
         for name, entry in pairs(subdirs) do
            table.insert(ops, entry.ch:get_operation())
         end
         return op.choice(unpack(ops))
      end
      local rx_op = recompute_rx_op()
      local occupancy = 0
      local stopping = false
      while not (stopping and occupancy == 0) do
         local event = rx_op:perform()
         if event == nil then
            -- Just pass.  Seems the two remove notifications have raced
            -- and the child won.
         elseif event.kind == 'add' then
            local name = event.name
            if is_dir(name) then
               if subdirs[name] == nil then
                  local cancel = cond.new()
                  local wait_op = cancel:wait_operation()
                  subdirs[name] =
                     { ch=recursive_directory_inventory_events(name, wait_op),
                       cancel=cancel }
                  rx_op = recompute_rx_op()
               else
                  warn('unexpected double-add for %s', name)
               end
            else
               occupancy = occupancy + 1
               tx:put({kind='creat', name=event.name})
            end
         elseif event.kind == 'mkdir' then
            occupancy = occupancy + 1
            tx:put(event)
         elseif event.kind == 'remove' then
            local name = event.name
            if subdirs[name] then
               -- Cancel the sub-stream, relying on the sub-stream to
               -- send rmdir.
               subdirs[name].cancel:signal()
            else
               occupancy = occupancy - 1
               tx:put({kind='rm', name=name})
            end
         elseif event.kind == 'rmdir' then
            occupancy = occupancy - 1
            local name = event.name
            if name == dir then
               stopping = true
            else
               tx:put(event)
               if subdirs[name] then
                  subdirs[name] = nil
                  rx_op = recompute_rx_op()
               end
            end
         elseif event.kind == 'creat' then
            occupancy = occupancy + 1
            tx:put(event)
         elseif event.kind == 'rm' then
            occupancy = occupancy - 1
            tx:put(event)
         else
            warn('unexpected event kind on %s: %s', event.name, event.kind)
         end
      end
      tx:put({kind='rmdir', name=dir})
      tx:put(nil)
   end)
   return tx
end

function selftest()
   print('selftest: lib.ptree.inotify')
   file_op.install_poll_io_handler()
   local tmpdir = os.getenv("TMPDIR") or "/tmp"
   local dir = tmpdir..'/'..lib.random_printable_string()
   assert(S.mkdir(dir, 'rusr,wusr,xusr'))
   local rx = recursive_directory_inventory_events(dir)
   local done = false
   local log = {}
   local function assert_log(expected)
      for i=1,#expected do
         assert(log[i] ~= nil, "short log")
         assert(lib.equal(log[i], expected[i]))
      end
      assert(#log == #expected)
      log = {}
   end
   -- For when you have ordering between adds and ordering between
   -- removes, but no ordering between adds and removes.
   local function assert_collated_log(mapping, expected)
      local collated = {}
      for k,v in pairs(mapping) do collated[v] = {} end
      for _,event in ipairs(log) do
         table.insert(collated[assert(mapping[event.kind])], event.name)
      end
      assert(lib.equal(expected, collated))
      log = {}
   end
   fiber.spawn(function ()
      for event in rx.get, rx do table.insert(log, event) end
      done = true
   end)

   local function mkdir(name)
      name = dir..'/'..name
      assert(S.mkdir(name, 'rusr,wusr,xusr'))
   end
   local function rmdir(name)
      name = dir..'/'..name
      assert(S.rmdir(name))
   end
   local function touch(name)
      name = dir..'/'..name
      assert(S.open(name, 'creat,rdwr,excl', 'rusr,wusr')):close()
   end
   local function rm(name)
      name = dir..'/'..name
      assert(S.unlink(name))
   end
   local function mv(old, new)
      old, new = dir..'/'..old, dir..'/'..new
      assert(S.rename(old, new))
   end

   -- Make some changes, let fibers process these events, and then see
   -- what the log says.
   touch("a"); touch("b"); mv("a", "c"); rm("b"); mkdir("d"); touch("d/a")
   for _=1,1e2 do fiber.current_scheduler:run() end
   assert_log {
      {kind='mkdir', name=dir},
      {kind='creat', name=dir..'/a'},
      {kind='creat', name=dir..'/b'},
      {kind='rm', name=dir..'/a'},
      {kind='creat', name=dir..'/c'},
      {kind='rm', name=dir..'/b'},
      {kind='mkdir', name=dir..'/d'},
      {kind='creat', name=dir..'/d/a'}}

   -- Here we rename a dir with one file.  There is a bit of
   -- nondeterminacy here because to our code, the removal of the old
   -- directory and the "creation" of the new one happen concurrently.
   -- The adds must be in order relative to each other, and likewise
   -- with the removes, but they can be interleaved in any way.
   mv("d", "e")
   for _=1,1e2 do fiber.current_scheduler:run() end
   assert_collated_log (
      { mkdir='a', creat='a', rmdir='r', rm='r' },
      { a={dir..'/e', dir..'/e/a'},
        r={dir..'/d/a', dir..'/d'}})

   rm("e/a"); rmdir("e")
   -- Because our code might delay delivery of a directory remove event
   -- by a few turns, to get reproducible results we need to synchronize
   -- the log here.
   for _=1,1e2 do fiber.current_scheduler:run() end
   assert_log {
      {kind='rm', name=dir..'/e/a'},
      {kind='rmdir', name=dir..'/e'}}

   rm("c"); assert(S.rmdir(dir))
   repeat fiber.current_scheduler:run() until done

   assert_log {
      {kind='rm', name=dir..'/c'},
      {kind='rmdir', name=dir}}

   print('selftest: ok')
end
