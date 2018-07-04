-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local lib = require("core.lib")
local pcap = require("lib.pcap.pcap")

local function usage(status)
   print(require("program.unhexdump.README_inc"))
   main.exit(status)
end

local function write_to_file(filename, content)
   if not lib.writefile(filename, content) then
      print(("Writing to %s failed, quitting"):format(filename))
      main.exit(1)
   end
end

local function write_packets(input, output)
   local bytes = {}
   local count = 0
   local function flush()
      if #bytes ~= 0 then
         pcap.write_record_header(output, #bytes)
         local s = string.char(unpack(bytes))
         output:write(string.char(unpack(bytes)))
         output:flush()
         bytes = {}
      end
      return count
   end
   local function add(byte)
      -- Adding the first byte of a packet means that we have one more
      -- packet than we did before.
      if #bytes == 0 then count = count + 1 end
      bytes[#bytes+1] = byte
   end
   while true do
      local line = input:read()
      if not line then
         -- EOF.
         return flush()
      elseif line:match('^%s*$') then
         -- Blank lines delimit packets.
         flush()
      else
         for hexpairs in line:split('[%p%sxX]+') do
            if not hexpairs:match('^%x*$') then
               error('Unexpected hexdump', hexpairs)
            elseif #hexpairs % 2 ~= 0 then
               error('Odd sequence of hex characters', hexpairs)
            else
               for pair in hexpairs:gmatch('%x%x') do
                  add(tonumber(pair, 16))
               end
            end
         end
      end
   end
end

function run(args)
   local truncate, append
   local handlers = {}
   function handlers.h() usage(0) end
   function handlers.t() truncate = true end
   function handlers.a() append = true end
   args = lib.dogetopt(args, handlers, "hta",
                       {help='h', truncate='t', append='a'})
   if #args ~= 1 then usage(1) end
   if truncate and append then usage(1) end

   local filename = args[1]
   local mode = "w"
   if truncate then mode = "w+" end
   if append then mode = "a+" end
   local file = assert(io.open(filename, mode..'b'))
   if file:seek('end') == 0 then
      pcap.write_file_header(file)
   else
      file:seek('set', 0)
      -- Assert that it's a pcap file.
      local header = pcap.read_file_header(file)
      file:seek('end', 0)
   end

   local count = write_packets(io.stdin, file)
   file:close()
   print("Wrote "..count.." packets to '"..filename.."'.")
end
