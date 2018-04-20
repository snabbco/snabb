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

local modes = {
   r='rdonly',
   w='wronly,creat,trunc',
   a='wronly,creat,append',
   ['r+']='rdwr',
   ['w+']='rdwr,creat,trunc',
   ['a+']='rdwr,creat,append'
}
do
   local binary_modes = {}
   for k,v in pairs(modes) do binary_modes[k..'b'] = v end
   for k,v in pairs(binary_modes) do modes[k] = v end
end

function io.open(filename, mode)
   if mode == nil then mode = 'r' end
   local flags = modes[mode]
   if flags == nil then return nil, 'invalid mode: '..tostring(mode) end
   -- This set of permissions is what fopen() uses.  Note that these
   -- permissions will be modulated by the umask.
   local fd, err = S.open(filename, flags, "rusr,wusr,rgrp,wgrp,roth,woth")
   if fd == nil then return nil, err end
   return file.fdopen(fd, flags)
end

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

function io.tmpfile()
   local name = os.tmpname()
   local f = io.open(name, 'w+')
   local close = f.io.close
   -- FIXME: Doesn't arrange to ensure the file is removed in all cases;
   -- calling close is required.
   function f.io:close()
      close()
      S.unlink(name)
   end
   return f
end

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
