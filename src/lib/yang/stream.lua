module(..., package.seeall)

local ffi = require("ffi")
local S = require("syscall")
local lib = require("core.lib")

local function round_up(x, y) return y*math.ceil(x/y) end

function open_output_byte_stream(filename)
   local fd, err =
      S.open(filename, "creat, wronly, trunc", "rusr, wusr, rgrp, roth")
   if not fd then
      error("error opening output file "..filename..": "..tostring(err))
   end
   local ret = { written = 0, name = filename }
   function ret:close()
      fd:close()
   end
   function ret:error(msg)
      self:close()
      error('while writing file '..filename..': '..msg)
   end
   function ret:write(ptr, size)
      assert(size)
      ptr = ffi.cast("uint8_t*", ptr)
      local to_write = size
      while to_write > 0 do
         local written, err = S.write(fd, ptr, to_write)
         if not written then self:error(err) end
         ptr = ptr + written
         self.written = self.written + written
         to_write = to_write - written
      end
   end
   function ret:write_ptr(ptr)
      self:align(ffi.alignof(ptr))
      self:write(ptr, ffi.sizeof(ptr))
   end
   function ret:rewind()
      fd:seek(0, 'set')
      ret.written = 0 -- more of a position at this point
   end
   function ret:write_array(ptr, type, count)
      self:align(ffi.alignof(type))
      self:write(ptr, ffi.sizeof(type) * count)
   end
   function ret:align(alignment)
      local padding = round_up(self.written, alignment) - self.written
      self:write(string.rep(' ', padding), padding)
   end
   return ret
end

local function mktemp(name, mode)
   if not mode then mode = "rusr, wusr, rgrp, roth" end
   -- FIXME: If nothing seeds math.random, this produces completely
   -- predictable numbers.
   local t = math.random(1e7)
   local tmpnam, fd, err
   for i = t, t+10 do
      tmpnam = name .. '.' .. i
      fd, err = S.open(tmpnam, "creat, wronly, excl", mode)
      if fd then
         fd:close()
         return tmpnam, nil
      end
      i = i + 1
   end
   return nil, err
end

function open_temporary_output_byte_stream(target)
   local tmp_file, err = mktemp(target)
   if not tmp_file then
      local dir = lib.dirname(target)
      error("failed to create temporary file in "..dir..": "..tostring(err))
   end
   local stream = open_output_byte_stream(tmp_file)
   function stream:close_and_rename()
      self:close()
      local res, err = S.rename(tmp_file, target)
      if not res then
         error("failed to rename "..tmp_file.." to "..target..": "..err)
      end
   end
   return stream
end

-- FIXME: Try to copy file into huge pages?
function open_input_byte_stream(filename)
   local fd, err = S.open(filename, "rdonly")
   if not fd then return 
      error("error opening "..filename..": "..tostring(err))
   end
   local stat = S.fstat(fd)
   local size = stat.size
   local mem, err = S.mmap(nil, size, 'read, write', 'private', fd, 0)
   fd:close()
   if not mem then error("mmap failed: " .. tostring(err)) end
   mem = ffi.cast("uint8_t*", mem)
   local pos = 0
   local ret = {
      name=filename,
      mtime_sec=stat.st_mtime,
      mtime_nsec=stat.st_mtime_nsec
   }
   function ret:close()
      -- FIXME: Currently we don't unmap any memory.
      -- S.munmap(mem, size)
      mem, pos = nil, nil
   end
   function ret:error(msg)
      error('while reading file '..filename..': '..msg)
   end
   function ret:read(count)
      assert(count >= 0)
      local ptr = mem + pos
      pos = pos + count
      if pos > size then
         self:error('unexpected EOF')
      end
      return ptr
   end
   function ret:align(alignment)
      self:read(round_up(pos, alignment) - pos)
   end
   function ret:seek(new_pos)
      if new_pos == nil then return pos end
      assert(new_pos >= 0)
      assert(new_pos <= size)
      pos = new_pos
   end
   function ret:read_ptr(type)
      ret:align(ffi.alignof(type))
      return ffi.cast(ffi.typeof('$*', type), ret:read(ffi.sizeof(type)))
   end
   function ret:read_array(type, count)
      ret:align(ffi.alignof(type))
      return ffi.cast(ffi.typeof('$*', type),
                      ret:read(ffi.sizeof(type) * count))
   end
   function ret:read_char()
      return ffi.string(ret:read(1), 1)
   end
   function ret:as_text_stream(len)
      local end_pos = size
      if len then end_pos = pos + len end
      return {
         name = ret.name,
         mtime_sec = ret.mtime_sec,
         mtime_nsec = ret.mtime_nsec,
         read = function(self, n)
            assert(n==1)
            if pos == end_pos then return nil end
            return ret:read_char()
         end,
         close = function() ret:close() end
      }
   end
   return ret
end

-- You're often better off using Lua's built-in files.  This is here
-- because it gives a file-like object whose FD you can query, for
-- example to get its mtime.
function open_input_text_stream(filename)
   return open_input_byte_stream(filename):as_text_stream()
end
