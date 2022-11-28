-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local ffi = require("ffi")

-- Helper for parsing C type declarations.
local function parse_type(str, start, is_member)
   local function err(msg, pos)
      io.stderr:write('ERROR: While parsing type:\n')
      io.stderr:write('ERROR:   '..str..'\n')
      io.stderr:write('ERROR:   '..string.rep(' ', pos - 1)..'^\n')
      io.stderr:write('ERROR: '..msg..'\n')
      error(msg, 2)
   end
   local function assert_match(str, pat, pos, what)
      local ret = { str:match(pat, pos) }
      if not ret[1] then err('bad '..what, pos) end
      return unpack(ret)
   end
   local t, array, member, pos
   -- See if it's a struct.
   t, pos = str:match('^%s*(struct%s*%b{})%s*()', start)
   -- Otherwise it might be a scalar.
   if not t then t, pos = str:match('^%s*([%a_][%w_]*)%s*()', start) end
   -- We don't do unions currently.
   if not t then err('invalid type', start) end
   -- If we're parsing a struct or union member, get the name.
   if is_member then
      member, pos = assert_match(str, '^([%a_][%w_]*)%s*()', pos, 'member name')
   end
   -- Parse off the array suffix, if any.
   if str:match('^%[', pos) then
      array, pos = assert_match(str, '^(%b[])%s*()', pos, 'array component')
   end
   if is_member then
      -- Members should have a trailing semicolon.
      pos = assert_match(str, '^;%s*()', pos, 'semicolon')
   else
      -- Nonmembers should parse to the end of the string.
      assert_match(str, '^()$', pos, 'suffix')
   end
   return t, array, member, pos
end

-- We want structural typing, not nominal typing, for Yang data.  The
-- "foo" member in "struct { struct { uint16 a; } foo; }" should not
-- have a unique type; we want to be able to instantiate a "struct {
-- uint16 a; }" and get a compatible value.  To do this, we parse out
-- nested "struct" types and only ever make one FFI type for each
-- compatible struct kind.  The user-facing interface is the "typeof"
-- function below; the "compile_type" helper handles nesting.
--
-- It would be possible to avoid this complexity by having the grammar
-- generate something other than a string "ctype" representation, but
-- then we don't have a type name to serialize into binary data.  We
-- might as well embrace the type strings.
local function compile_type(name)
   local function maybe_array_type(t, array)
      -- If ARRAY is something like "[10]", make a corresponding type.
      -- Otherwise just return T.
      if array then return ffi.typeof('$'..array, t) end
      return t
   end
   local parsed, array = parse_type(name, 1, false)
   local ret
   if parsed:match('^struct[%s{]') then
      -- It's a struct type; parse out the members and rebuild.
      local struct_type = 'struct { '
      local struct_type_args = {}
      local function add_member(member_type, member_name)
         struct_type = struct_type..'$ '..member_name..'; '
         table.insert(struct_type_args, member_type)
      end
      -- Loop from initial "struct {" to final "}".
      local pos = assert(parsed:match('^struct%s*{%s*()'))
      while not parsed:match('^}$', pos) do
         local mtype, mname, marray
         mtype, marray, mname, pos = parse_type(parsed, pos, true)
         -- Recurse on mtype by calling the caching "typeof" defined
         -- below.
         add_member(maybe_array_type(typeof(mtype), marray), mname)
      end
      struct_type = struct_type..'}'
      ret = ffi.typeof(struct_type, unpack(struct_type_args))
   else
      -- Otherwise the type is already structural and we can just use
      -- ffi.typeof.
      ret = ffi.typeof(parsed)
   end
   return maybe_array_type(ret, array)
end

local type_cache = {}
function typeof(name)
   assert(type(name) == 'string')
   if not type_cache[name] then type_cache[name] = compile_type(name) end
   return type_cache[name]
end
