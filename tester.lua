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
    description = {},
    code = {},
    tags = tags_from_path(fn),
  }
  local current_test = prelude
  local function store_test()
    if current_test and current_test~=prelude then 
      current_test.code = table.concat(current_test.code,"\n")
      current_test.description = table.concat(current_test.description,"\n")
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
  prelude.code = table.concat(prelude.code,"\n")
  prelude.description = table.concat(prelude.description,"\n")
  return tests, lookup_tests, prelude
end


return {
  parse = parse_test
}
