-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

-- snabb rrdcat: summarize the data recorded in a RRD database with a
-- normalized ASCII plot. Skips (with indication) over zero or unknown data
-- rows.

local rrd = require("lib.rrd")
local lib = require("core.lib")

local usage = require("program.rrdcat.README_inc")

local long_opts = {
   help = "h",
   source = "s",
   interval = "i",
   ["list-contents"] = "l"
}

function run (args)
   local opt = {}
   local source, interval, list_contents
   function opt.h () print(usage) main.exit(0) end
   function opt.s (arg) source = arg end
   function opt.i (arg) interval = tonumber(arg) end
   function opt.l () list_contents = true end
   args = lib.dogetopt(args, opt, "hs:i:l", long_opts)

   if #args ~= 1 then print(usage) main.exit(1) end
   local file = args[1]

   local ok, db = pcall(rrd.open_file, file)
   if not ok then
      print("Could not open: "..file)
      print(db)
      main.exit(1)
   end

   local sources, default_source = {}
   for _, source, typ, heartbeat, min, max in db:isources() do
      sources[source] = {typ=typ, heartbeat=heartbeat, min=min, max=max}
      default_source = default_source or source
   end

   local function list_sources ()
      print("Available sources:")
      for source, s in pairs(sources) do
         print('', ("%s (type: %s, heartbeat: %d, min: %.2f, max: %.2f)")
                  :format(source, s.typ, s.heartbeat,
                          isnan(s.min) and -1/0 or s.min,
                          isnan(s.max) and 1/0 or s.max))
      end
   end

   local intervals, default_interval = {}, 0
   for _, cf, _, window in db:iarchives() do
      local interval = window * tonumber(db.fixed.seconds_per_pdp)
      intervals[interval] = intervals[interval] or {}
      table.insert(intervals[interval], cf)
      default_interval = math.max(default_interval, interval)
   end

   local function list_intervals ()
      print("Available intervals:")
      for interval, cfs in pairs(intervals) do
         print('', ("%d (%s)"):format(interval, table.concat(cfs, ' ')))
      end
   end

   if list_contents then
      list_sources()
      list_intervals()
      print("Last updated:")
      print('', os.date("%c", db:last_update()))
      main.exit(0)
   end

   if source and not sources[source] then
      print("No such source: "..source)
      list_sources()
      main.exit(1)
   end
   source = source or default_source

   if interval and not intervals[interval] then
      print("Interval not available: "..interval)
      list_intervals()
      main.exit(1)
   end
   interval = interval or default_interval

   -- Compile CDPs for source at intervals.
   -- (Inluding unknown (NaN) CDPs.)
   local ts = {}   -- { t, t-1, t-2, ...}
   local rows = {} -- { [t] = { [cf] = { val=x } } }
   -- Return row matching source and interval from ref (if any is available.)
   local function select_row (ref)
      for name, src in pairs(ref) do
         if name == source then
            local row
            for cf, values in pairs(src.cf) do
               for _,x in ipairs(values) do
                  if x.interval == interval then
                     row = row or {}
                     row[cf] = {val=x.value}
                  end
               end
            end
            return row
         end
      end
   end
   -- Collect rows.
   for t = math.ceil(db:last_update()/60)*60, 0, -interval do
      local row = select_row(db:ref(t))
      if row then
         ts[#ts+1] = t
         rows[t] = row
      elseif t < db:last_update() then
         -- No row and t is before last update:
         -- looks like end of data.
         break
      end
   end
   -- Sort timestamps for data points chronologically.
   table.sort(ts)

   -- Select any CDP in row.
   local function any (row)
      return row.max or row.average or row.last or row.min
   end

   -- Compute minimum and maximum value in selected CDPs.
   local minval, maxval
   for _, row in pairs(rows) do
      for cf, cdp in pairs(row) do
         if not isnan(cdp.val) then
            maxval = math.max(maxval or 0, cdp.val)
            minval = math.min(minval or maxval, cdp.val)
         end
      end
   end

   -- Compute width-relative value for each CDP.
   local width = 20
   for _, row in pairs(rows) do
      for cf, cdp in pairs(row) do
         if not isnan(cdp.val) then
            cdp.rel = math.ceil((cdp.val/maxval) * width)
         end
      end
   end

   -- Format timestamp label every four rows.
   local tl_delta = 3
   local tl_delta_ctr = 0
   local date
   local function tl (out, t)
      if tl_delta_ctr == 0 then
         date = os.date("%c", t)
         out:write(date)
         tl_delta_ctr = tl_delta
      else
         out:write((" "):rep(#date))
         tl_delta_ctr = tl_delta_ctr - 1
      end
   end

   -- Plot a width-relative distribution for row.
   local function plot (out, row)
      local fill = 0
      if isnan(any(row).val) then
         -- Unknown data in row.
         out:write(" ?")
      else
         -- Plot row.
         out:write(" [")
         if row.min then
            out:write((" "):rep(math.max(0, row.min.rel-fill-1)))
            out:write(("n"):rep(math.min(1, row.min.rel-fill)))
            fill = row.min.rel
         end
         if row.average then
            local bar = (row.min and row.max) and "-" or " "
            out:write(bar:rep(math.max(0, row.average.rel-fill-1)))
            out:write(("a"):rep(math.min(1, row.average.rel-fill)))
            fill = row.average.rel
         elseif row.last then
            local bar = (row.min and row.max) and "-" or " "
            out:write(bar:rep(math.max(0, row.last.rel-fill-1)))
            out:write(("l"):rep(math.min(1, row.last.rel-fill)))
            fill = row.last.rel
         end
         if row.max then
            out:write(("-"):rep(math.max(0, row.max.rel-fill-1)))
            out:write(("m"):rep(math.min(1, row.max.rel-fill)))
            fill = row.max.rel
         end
      end
      out:write((" "):rep(width-fill))
   end

   -- Pretty-print numeric value.
   local function pp (val)
      local function round (n)
         -- round to nearest integer
         return math.floor(n+.5)
      end
      if val == 0 then
         return "-"
      elseif val < 1e2 then
         return ("%.2f"):format(val)
      elseif val < 1e3 then
         return tostring(round(val))
      elseif val < 1e6 then
         return ("%dK"):format(round(val/1e3))
      else
         return ("%dM"):format(round(val/1e6))
      end   
   end

   -- Format value summary for row.
   local function vals (out, row)
      if isnan(any(row).val) then
         -- Unknown data in row, do not try to summarize.
         return
      end
      if row.min then
         out:write((" min:%s"):format(pp(row.min.val)))
      end
      if row.average then
         out:write((" avg:%s"):format(pp(row.average.val)))
      end
      if row.last then
         out:write((" lst:%s"):format(pp(row.last.val)))
      end
      if row.max then
         out:write((" max:%s"):format(pp(row.max.val)))
      end
   end

   -- Snip after three consecutive zero or unknown data rows.
   local snipz_after = 3
   local snipz_thr = snipz_after
   local function snipz (val)
      if val > 0 and not isnan(val) then
         snipz_thr = snipz_after
      else
         if snipz_thr == 0 then return true
         else snipz_thr = snipz_thr - 1 end
      end
   end

   -- Print and plot non-zero row clusters.
   local snipped
   for _, t in ipairs(ts) do
      if not snipz(any(rows[t]).val) then
         tl(io.stdout, t)
         plot(io.stdout, rows[t])
         vals(io.stdout, rows[t])
         io.stdout:write("\n")
         snipped = nil
      else
         if not snipped then
            io.stdout:write("...\n")
            snipped = true
            tl_delta_ctr = 0 -- reset timestamp label interval
         end
      end
   end

   -- fin
   main.exit(0)
end

-- NaN values indicate unknown data.
function isnan (x) return x ~= x end
