local lfs = require("lfs")
local tconcat = table.concat

--- Shallow table copy
local function cp(t)
  local t1 = {}
  for k,v in pairs(t) do t1[k]=v end
  return t1
end

--- Path tokenizer, builds a table t for which t.token=true
-- @param fn string containing a filename (fullpath)
-- @return table for which keys token = true
local function tags_from_path(fn)
  local tags = {}
  for token in fn:gmatch("[^\\/]+") do
    local token_lua = token:match("(.*)%.lua$")
    tags[token_lua or token] = true
  end
  return tags
end

-- Patterns for parsing out test data.
local identifier_pat = "([_%a][_%w]*)"
local delim_pat = "^%-%-%-"
local name_pat = delim_pat.."%s*(.*)"
local desc_pat = "^%-%-(.*)"
local tag_pat = "%+"..identifier_pat
local attrib_pat = "@"..identifier_pat.."%s*:%s*([^@]*)"

--- Parser for the tests.
-- @param fn string containing a filename (fullpath)
-- @return array containing test specs (name, code, description, tags)
local function parse_test(fn)
  local tests = {}
  local lookup = {}
  local prelude = {
    name = "prelude of "..fn,
    fn = fn,
    description = {},
    code = {},
    tags = tags_from_path(fn),
    attributes = {},
  }
  local current_test = prelude
  local function store_test()
    tests[#tests+1] = current_test
    lookup[current_test.name] = #tests
  end
  for line in io.lines(fn) do
    if line:match(delim_pat) then
      -- Next test is reached
      store_test()
      local testname = line:match(name_pat)
      if lookup[testname] then
        error("Test "..testname.." is defined twice in the same file. Please give the tests unique names.")
      end
      -- Add current test to the tests table and start new current test table.
      current_test = {
        name = testname,
        fn = fn,
        description = cp(prelude.description),
        tags = cp(prelude.tags),
        code = cp(prelude.code),
        attributes = cp(prelude.attributes),
      }
    elseif line:match(desc_pat) and #current_test.code==#prelude.code then
      -- Continue building current test description, and possibly extract tags and key-value pairs
      current_test.description[#current_test.description+1] = line:match(desc_pat)
      for tag in line:gmatch(tag_pat) do
        current_test.tags[tag] = true
      end
      for key,value in line:gmatch(attrib_pat) do
        current_test.attributes[key] = value:gsub("%s*$","")
      end
    else
      current_test.code[#current_test.code+1] = line
    end
  end
  store_test()
  return tests
end

-- Recursively parse the path and store the tests in test_index
-- @param path string containing a path to a file or directory
-- @param test_index array containing the tables with tests per file
local function recursive_parse(path,test_index)
  local att, err = lfs.attributes(path)
  if not att then 
    error("Could not parse "..path..": "..err)
  end
  if att.mode=="directory" then
    for path2 in lfs.dir(path) do
      if path2~=".." and path2~="." then
        recursive_parse(path.."/"..path2,test_index)
      end
    end
  elseif att.mode=="file" and path:match("%.lua$") then
    test_index[#test_index+1] = parse_test(path)
  end
end

--- Walk the directory tree and index tests.
-- @param paths array of paths that should be indexed.
-- @return array of tables containing tests returned by parse
local function index_tests(paths)
  local test_index = {}
  for _,path in ipairs(paths) do
    recursive_parse(path,test_index)
  end
  return test_index
end

--- Build the string containing the chunk of a single test, including name and
-- description.
-- @param test table containing a test's name, description and code
-- @return string containing the code snippet for the test, including comments.
local function build_codestring(test)
  return tconcat({
    "--- ", test.name,
    #test.description>0 and "\n--" or "",
    tconcat(test.description,"\n--"), "\n",
    tconcat(test.code,"\n")
  })
end

--- Extract a test into a directory
-- @param test the test table returned by parse, containing name, description, tags, code
-- @param fn string containing filename where the test should be extracted (default:os.tmpname())
-- @return filename to where the test was extracted
local function extract_test(test,fn)
  fn = fn or os.tmpname()..".lua"
  local f = io.open(fn,"w")
  if not f then
    error("Could not write to file "..fn)
  end
  f:write(build_codestring(test))
  f:close()
  return fn
end

--- Run a single test, possibly externally with luajitcmd.
-- @param test single test object containing name, description, tags, code.
-- @param verbose boolean indicating verbosity
-- @param luajitcmd string containing the luajit command to run external tests.
-- If luajitcmd is defined, the test is extracted into a file and run externally.
-- If left empty, the test is run internally with pcall.
-- @return true (pass) or false (fail)
-- @return msg error message in case of failure
local function run_single_test(test,verbose,luajitcmd)
  if luajitcmd then
    local fn = extract_test(test)
    local ret = os.execute(luajitcmd.." "..fn)
    return ret==0
  end
  local code = build_codestring(test)
  local load_ok, load_res = pcall(loadstring,code)
  if load_ok then
    local ok, res = pcall(load_res)
    if verbose then 
      io.write(ok and "PASS " or "FAIL ",test.name,"\n")
      if not ok then io.write("    "..(res or "(no error message)"),"\n") end
    end
    return ok, res
  else
    if verbose then 
      io.write("SYNT ",test.name,load_res or "(no error message)","\n")
    end
    return load_ok, load_res
  end
end

--- Recursively run tests in paths.
-- @param paths array of paths to recursively run tests in.
-- @param verbose boolean indicating verbosity
-- @param luajitcmd string containing the luajit command to run external tests.
-- If luajitcmd is defined, the test is extracted into a file and run externally.
-- If left empty, the test is run internally with pcall.
-- @return number of passed tests
-- @return number of failed tests
-- @return array of failed tests
-- @return array of corresponding error messages
local function run_tests(test_index,verbose,luajitcmd)
  local pass, fail = 0,0
  local failed_tests = {}
  local errors = {}
  for i,test_block in ipairs(test_index) do
    for j,test in ipairs(test_block) do
      local ok, res = run_single_test(test,verbose,luajitcmd)
      if ok then
        pass = pass+1
      else
        fail = fail+1
        failed_tests[#failed_tests+1] = test
        errors[#errors+1] = res
      end
    end
  end
  return pass, fail, failed_tests, errors
end

--- Check whether tags are in tags_inc and none are in tags_exc.
-- If tags_inc is empty, default inclusion is true.
-- @param tags Array of tags to test
-- @param tags_inc Array of tags to include
-- @param tags_exc Array of tags to exclude
-- @return boolean indicating inclusion
local function check_tags(tags,tags_inc,tags_exc)
  local include = false
  if #tags_inc==0 then include = true end
  for _,tag_inc in ipairs(tags_inc) do
    if tags[tag_inc] then
      include = true
      break
    end
  end
  if not include then return false end
  for _,tag_exc in ipairs(tags_exc) do
    if tags[tag_exc] then
      return false 
    end
  end
  return true
end

--- Select tests with tags_inc without tags_exc.
-- If tags_inc is empty, select all tests by default.
-- @param test_index array of test_blocks 
-- @param tags_inc array of tags to include
-- @param tags_exc array of tags to exclude
local function filter_tests(test_index,tags_inc,tags_exc)
  local tests_filtered = {}
  for i,test_block in ipairs(test_index) do
    local tests_i
    for j, test in ipairs(test_block) do
      if check_tags(test.tags,tags_inc,tags_exc) then
        tests_i = tests_i or {}
        tests_i[#tests_i+1]= test 
      end
    end
    tests_filtered[#tests_filtered+1] = tests_i
  end
  return tests_filtered
end

return {
  parse = parse_test,
  index = index_tests,
  extract = extract_test,
  run_single = run_single_test,
  run = run_tests,
  filter = filter_tests,
}
