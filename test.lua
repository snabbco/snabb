local t = require("tester")
local tconcat, iowrite = table.concat, io.write
local tagpat_inc = "^%+([A-Za-z_][A-Za-z0-9_]*)$"
local tagpat_exc = "^%-([A-Za-z_][A-Za-z0-9_]*)$"
local args = {...}
local paths, tags_inc, tags_exc = {}, {}, {}
local verbose = false

local function print_help()
  io.write[[
Usage: luajit test.lua path1 path2 +tagtofilter +orthistag -tagtoexclude -andthistag
Options:
  path      Recursively include tests in path. Default: test
  +tag_inc  Include only tests with tag tag_inc. Multiple include tags are ORed.
  -tag_exc  Exclude tests with tag tag_exc.
  --help    Print this help message.
  --verbose Explicitly list all tests.
]]
end

for _,arg in ipairs(args) do
  if not arg:match("^[+-]") then
    paths[#paths+1]=arg
  elseif arg:match(tagpat_inc) then
    tags_inc[#tags_inc+1]=arg:match(tagpat_inc)
  elseif arg:match(tagpat_exc) then
    tags_exc[#tags_exc+1]=arg:match(tagpat_exc)
  elseif arg:match("%-%-verbose") then
    verbose = true
  elseif arg:match("%-%-help") then
    print_help()
    return
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
local pass, fail, failed_tests, errors = t.run(index,verbose)

iowrite("Passed ",pass,"/",pass+fail," tests.\n")
if fail==0 then return end

iowrite("Failed tests:\n")
for i=1,fail do
  iowrite(string.rep("-",72),"\n")
  iowrite("Name: ",failed_tests[i].name,"\n")
  iowrite("Error: ",errors[i] or "(no error message)","\n")
  iowrite("Filename: ",t.extract(failed_tests[i]),"\n")
end

