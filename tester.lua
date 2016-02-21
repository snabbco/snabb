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

--- Parser for the tests.
-- @param fn string containing a filename (fullpath)
-- @return array containing test specs (name, code, description, tags)
-- @return lookup table for tests
-- @return prelude table containing prelude code, description and tags.
local function parse_test(fn)
  local tests = {}
  local lookup_tests = {}
  local prelude = {
    name = "prelude of "..fn,
    fn = fn,
    description = {},
    code = {},
    tags = tags_from_path(fn),
  }
  local current_test = prelude
  local function store_test()
    if current_test~=prelude then
      tests[#tests+1] = current_test
      lookup_tests[current_test.name] = #tests
    end
  end
  for line in io.lines(fn) do
    if line:match("^%-%-%-") then
      -- Next test is reached
      store_test()
      local testname = line:match("^%-%-%-%s*(.*)$")
      if lookup_tests[testname] then
        error("Test "..testname.." is defined twice in the same file. Please give the tests unique names.")
      end
      -- Add current test to the tests table and start new current test table.
      current_test = {
        name = testname,
        fn = fn,
        description = cp(prelude.description),
        tags = cp(prelude.tags),
        code = cp(prelude.code),
      }
    elseif line:match("^%-%-") and #current_test.code==#prelude.code then
    -- Continue building current test description (and possibly tags)
      current_test.description[#current_test.description+1] = line:match("^%-%-%s*(.*)$")
      for tag in line:gmatch("%+([A-Za-z_][A-Za-z0-9_]*)") do
        current_test.tags[tag] = true
      end
    else
      current_test.code[#current_test.code+1] = line
    end
  end
  store_test()
  tests[0] = prelude
  return tests, lookup_tests
end

-- Recursively parse the path and store the tests in test_index
-- @param path string containing a path to a file or directory
-- @param test_index array containing the tables with {tests,lookup,prelude}
-- @param test_index_lookup lookup table containing keys = paths of the test
-- files and values = respective indices in test_index
local function recursive_parse(path,test_index,test_index_lookup)
  local att = lfs.attributes(path)
  if att.mode=="directory" then
    for path2 in lfs.dir(path) do
      if path2~=".." and path2~="." then
        recursive_parse(path.."/"..path2,test_index,test_index_lookup)
      end
    end
  elseif att.mode=="file" and path:match("%.lua$") then
    local tests, tests_lookup, prelude = parse_test(path)
    if tests then
      test_index[#test_index+1] = {tests=tests, lookup=tests_lookup, prelude=prelude}
      test_index_lookup[path] = #test_index
    end
  end
end

--- Walk the directory tree and index tests.
-- @param paths array of paths that should be indexed.
-- @return array of tables containing { tests, lookup, prelude } as returned by
-- parse
-- @return lookup table containing keys = paths of the test files and values =
-- respective indices in test_index
local function index_tests(paths)
  local test_index = {}
  local test_index_lookup = {}
  for _,path in ipairs(paths) do
    recursive_parse(path,test_index,test_index_lookup)
  end
  return test_index, test_index_lookup
end

--- Build the string containing the chunk of a single test, including name and
-- description.
-- @param test table containing a test's name, description and code
-- @return string containing the code snippet for the test, including comments.
local function build_codestring(test)
  return tconcat({
    "--- ", test.name,
    "\n--", tconcat(test.description,"\n--"), "\n",
    tconcat(test.code,"\n")
  })
end

--- Extract a test into a directory
-- @param test the test table returned by parse, containing name, description, tags, code
-- @param fn string containing filename where the test should be extracted (default:os.tmpname())
-- @return filename to where the test was extracted
local function extract_test(test,fn)
  fn = fn or os.tmpname()
  local f = io.open(fn,"w")
  if not f then
    error("Could not write to file "..fn)
  end
  f:write(build_codestring(test))
  f:close()
  return fn
end

--- Run a single test, possibly externally with luajitcmd.
-- @param test: single test object containing name, description, tags, code.
-- @param luajitcmd string containing the luajit command to run external tests.
-- If luajitcmd is defined, the test is extracted into a file and run externally.
-- If left empty, the test is run internally with pcall.
-- @return true (pass) or false (fail)
-- @return msg error message in case of failure
local function run_single_test(test,luajitcmd)
  if luajitcmd then
    local fn = extract_test(test)
    local ret = os.execute(luajitcmd.." "..fn)
    return ret==0
  end
  local code = build_codestring(test)
  local load_ok, load_res = pcall(loadstring,code)
  if load_ok then
    return pcall(load_res)
  else
    return load_ok, load_res
  end
end

-- Recursively run tests in paths.
-- @param paths array of paths to recursively run tests in.
-- @param luajitcmd string containing the luajit command to run external tests.
-- If luajitcmd is defined, the test is extracted into a file and run externally.
-- If left empty, the test is run internally with pcall.
-- @return number of passed tests
-- @return number of failed tests
-- @return array of failed tests
-- @return array of corresponding error messages
local function run_tests(paths,luajitcmd)
  local pass, fail = 0,0
  local failed_tests = {}
  local errors = {}
  local test_index = index_tests(paths)
  for i,test_block in ipairs(test_index) do
    -- key 0 is the prelude block.
    for j=0,#test_block.tests do
      local test = test_block.tests[j]
      local ok, res = run_single_test(test)
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

return {
  parse = parse_test,
  index = index_tests,
  extract = extract_test,
  run_single = run_single_test,
  run = run_tests,
}
