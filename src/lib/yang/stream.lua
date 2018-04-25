module(..., package.seeall)

local ffi = require("ffi")
local S = require("syscall")
local lib = require("core.lib")
local file = require("lib.stream.file")

-- FIXME: Try to copy file into huge pages?
function open_input_byte_stream(filename)
   local stream, err = file.open(filename, "r")
   if not stream then
      error("error opening "..filename..": "..tostring(err))
   end
   local stat = stream.io.fd:stat()
   local ret = {
      name=filename,
      mtime_sec=stat.st_mtime,
      mtime_nsec=stat.st_mtime_nsec
   }
   function ret:close()
      stream:close()
   end
   function ret:error(msg)
      error('while reading file '..filename..': '..msg)
   end
   function ret:read(count)
      local buf = ffi.new('uint8_t[?]', count)
      stream:read_bytes_or_error(buf, count)
      return buf
   end
   function ret:seek(whence, new_pos)
      return stream:seek(whence, new_pos)
   end
   function ret:read_struct(type)
      return stream:read_struct(nil, type)
   end
   function ret:read_array(type, count)
      return stream:read_array(nil, type, count)
   end
   function ret:read_scalar(type)
      return stream:read_scalar(nil, type)
   end
   function ret:read_char()
      return stream:read_char()
   end
   function ret:read_string()
      return stream:read_all_chars()
   end
   function ret:as_text_stream()
      return {
         name = ret.name,
         mtime_sec = ret.mtime_sec,
         mtime_nsec = ret.mtime_nsec,
         read = function(self, n)
            assert(n==1)
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
