-- test.lua
--
-- Recursively run tests in the given paths, filtered by the given tags.
-- Failed tests are extracted to the directory "failed_tests", and error
-- details are appended.

local t = require("tester")
local tconcat, iowrite = table.concat, io.write
local tagpat_inc = "^%+([_%a][_%w]*)$"
local tagpat_exc = "^%-([_%a][_%w]*)$"
local paths, tags_inc, tags_exc = {}, {}, {}
local verbose = false
local arg = arg or {...}
local runcmd
local function print_help()
  io.write[[
Usage: luajit test.lua path1 path2 +tagtofilter +orthistag -tagtoexclude -andthistag
Options:
  path      Recursively include tests in path. Default: test
  +tag_inc  Include only tests with tag tag_inc. Multiple include tags are ORed.
  -tag_exc  Exclude tests with tag tag_exc.
  --help    Print this help message.
  --verbose Explicitly list all tests.
  --runcmd='cmd'
            If runcmd is defined, Command to run the tests with, externally, e.g.
              --runcmd="luajit -joff"
]]
end

for _,a in ipairs(arg) do
  if not a:match("^[+-]") then
    paths[#paths+1]=a
  elseif a:match(tagpat_inc) then
    tags_inc[#tags_inc+1]=a:match(tagpat_inc)
  elseif a:match(tagpat_exc) then
    tags_exc[#tags_exc+1]=a:match(tagpat_exc)
  elseif a:match("%-%-verbose") then
    verbose = true
  elseif a:match("%-%-help") then
    print_help()
    return
  elseif a:match("%-%-runcmd") then
    runcmd = a:match("%-%-runcmd=(.*)")
  end
end

if #paths==0 then paths[1]="test" end
iowrite("Running tests in \"",tconcat(paths,"\",\""),"\"")
if #tags_inc > 0 then 
  iowrite(" with tags ",tconcat(tags_inc,","))
end
if #tags_exc > 0 then
  iowrite(" but without tags ",tconcat(tags_exc,","))
end
iowrite("\n")

local index = t.index(paths)
index = t.filter(index,tags_inc,tags_exc)
local pass, fail, failed_tests, errors = t.run(index,verbose,runcmd)

iowrite("Passed ",pass,"/",pass+fail," tests.\n")
if fail==0 then return end

local function report_fail(test,err)
  local extfn = t.extract(test,"failed_tests")
  iowrite("----------------------------------------------------------",
          "\nname: ",test.name,
          "\nerror: ",err or "(no error message)",
          "\nsource file: ",test.fn,
          "\nextracted to file: ",extfn,
          "\n")
  -- Append error message for completeness
  local extf = io.open(extfn,"a")
  if extf then
    extf:write("\n--[===[\nTest failed at ",os.date(),
               "\nruncmd: ",runcmd or "(internal pcall)",
               "\nerror:\n",err or "(no error message)",
               "\n]===]\n")
  end
end

iowrite("Failed tests:\n")
for i,failed_test in ipairs(failed_tests) do
  report_fail(failed_test,errors[i])
end

