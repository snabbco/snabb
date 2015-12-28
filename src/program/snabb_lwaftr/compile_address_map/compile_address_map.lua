module(..., package.seeall)

local ffi = require('ffi')
local lib = require('core.lib')
local S = require('syscall')
local address_map = require("apps.lwaftr.address_map")

function show_usage(code)
   print(require("program.snabb_lwaftr.compile_address_map.README_inc"))
   main.exit(code)
end

function parse_args(args)
   local handlers = {}
   function handlers.h() show_usage(0) end
   args = lib.dogetopt(args, handlers, "h", { help="h" })
   if #args < 1 or #args > 2 then show_usage(1) end
   return unpack(args)
end

local function mktemp(name, mode)
   if not mode then mode = "rusr, wusr, rgrp, roth" end
   t = math.random(1e7)
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

function run(args)
   local in_file, out_file = parse_args(args)
   local map = address_map.compile(in_file)
   if not out_file then out_file = in_file:gsub("%.txt$", "")..'.map' end
   local tmp_file, err = mktemp(out_file)
   if not tmp_file then
      local dir = ffi.string(ffi.C.dirname(out_file))
      io.stderr:write(
         "Failed to create temporary file in "..dir..": "..err.."\n")
      main.exit(1)
   end
   map:save(tmp_file)
   local res, err = S.rename(tmp_file, out_file)
   if not res then
      io.stderr:write(
         "Failed to rename "..tmp_file.." to "..out_file..": "..err.."\n")
      main.exit(1)
   end
   main.exit(0)
end
