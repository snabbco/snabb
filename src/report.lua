-- report.lua -- Reporting status for operation and maintenance
-- 
-- Copyright 2012 Snabb GmbH. See the file COPYING for license details.

module("report",package.seeall)

local lfs = require("lfs")
local ffi = require("ffi")

commanddir = nil

-- Scan commanddir/* for scripts to execute.
-- For each script S we first execute with output to S.out and then remove S.
function scan ()
   local oldstdout, oldstderr = io.stdout, io.stderr
   if commanddir ~= nil then
      for filename in lfs.dir(commanddir) do
	 if string.match(filename, ".out") == nil then
	    path = commanddir.."/"..filename
	    local output = io.open(path..".out", "w+")
	    io.stdout, io.stderr = output, output
	    local status, value = pcall(function () dofile(path) end)
	    if status == false then
	       output:write(tostring(value))
	    end
	    output:close()
	    os.remove(path)
	 end
      end
      io.stdout, io.stderr = oldstdout, oldstderr
   end
end   

-- Functions that can be interesting to call

function dump_forwarding_table()
   io.stdout:write("-- Snabb Switch forwarding table:\n")
   for key,value in pairs(switch.fdb.table) do
      io.stdout:write(formatmac(key) .. " -> " .. tostring(value) .. "\n")
   end
end

function formatmac (string)
   local byte = function (c) return string.format(":%02X",string.byte(c)) end
   return string.sub(string.gsub(string, ".", byte), 2)
end

