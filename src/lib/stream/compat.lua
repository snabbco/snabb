-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Shim to replace Lua's built-in IO module with streams.

module(..., package.seeall)

local stream = require('lib.stream')
local file = require('lib.stream.file')
local S = require('syscall')

local io = {}

function io.close(file)
   if file == nil then file = io.current_output end
   file:close()
end

function io.flush()
   io.current_output:flush()
end

function io.input(new)
   if new == nil then return io.current_input end
   if type(new) == string then new = io.open(new, 'r') end
   io.current_input = new
end

function io.lines(filename, ...)
   if filename == nil then return io.current_input:lines() end
   local stream = io.open(filename, 'r')
   local iter = stream:lines(...)
   return function ()
      local line = { iter() }
      if line[1] == nil then
         stream:close()
         return nil
      end
      return unpack(line)
   end
end

io.open = file.open

function io.output(new)
   if new == nil then return io.current_output end
   if type(new) == string then new = io.open(new, 'w') end
   io.current_output = new
end

function io.popen(prog, mode)
   return file.popen(prog, mode)
end

function io.read(...)
   return io.current_input:read(...)
end

io.tmpfile = file.tmpfile

function io.type(x)
   if not stream.is_stream(x) then return nil end
   if not x.io then return 'closed file' end
   return 'file'
end

function io.write(...)
   return io.current_output:write(...)
end

function install()
   if _G.io == io then return end
   _G.io = io
   io.stdin = file.fdopen(S.t.fd(0), 'rdonly')
   io.stdout = file.fdopen(S.t.fd(1), 'wronly')
   io.stderr = file.fdopen(S.t.fd(2), 'wronly')
   if io.stdout.io.fd:isatty() then io.stdout:setvbuf('line') end
   io.stderr:setvbuf('no')
   io.input(io.stdin)
   io.output(io.stdout)
end

function selftest()
   print('selftest: lib.stream.compat')

   _G.io.write('before\n')
   install()
   _G.io.write('after\n')
   assert(_G.io == io)

   print('selftest: ok')
end
