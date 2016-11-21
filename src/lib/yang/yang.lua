-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local lib = require("core.lib")
local schema = require("lib.yang.schema")
local data = require("lib.yang.data")
local binary = require("lib.yang.binary")
local stream = require("lib.yang.stream")
local util = require("lib.yang.util")

load_schema = schema.load_schema
load_schema_file = schema.load_schema_file
load_schema_by_name = schema.load_schema_by_name

load_data_for_schema = data.load_data_for_schema
load_data_for_schema_by_name = data.load_data_for_schema_by_name

print_data_for_schema = data.print_data_for_schema
print_data_for_schema_by_name = data.print_data_for_schema_by_name
string_output_file = util.string_output_file

compile_data_for_schema = binary.compile_data_for_schema
compile_data_for_schema_by_name = binary.compile_data_for_schema_by_name

load_compiled_data_file = binary.load_compiled_data_file

local params = {
   verbose = {},
   schema_name = {required=true},
   revision_date = {},
}

-- Load the configuration from FILENAME.  If it's compiled, load it
-- directly.  Otherwise if it's source, then try to load a corresponding
-- compiled file instead if possible.  If all that fails, actually parse
-- the source configuration, and try to residualize a corresponding
-- compiled file so that we won't have to go through the whole thing
-- next time.
function load_configuration(filename, opts)
   opts = lib.parse(opts, params)

   function maybe(f, ...)
      local function catch(success, ...)
         if success then return ... end
      end
      return catch(pcall(f, ...))
   end
   local function err_msg(msg, ...)
      return string.format('%s: '..msg, filename, ...)
   end
   local function err(msg, ...) error(err_msg(msg, ...)) end
   local function log(msg, ...)
      io.stderr:write(err_msg(msg, ...)..'\n')
      io.stderr:flush()
   end
   local function assert(exp, msg, ...)
      if exp then return exp else err(msg, ...) end
   end
   local function expect(expected, got, what)
      assert(expected == got, 'expected %s %s, but got %s', what, expected, got)
   end

   local function is_fresh(expected, got)
   end
   local function load_compiled(stream, source_mtime)
      local compiled = binary.load_compiled_data(stream)
      if opts.schema_name then
         expect(opts.schema_name, compiled.schema_name, 'schema name')
      end
      if opts.revision_date then
         expect(opts.revision_date, compiled.revision_date,
                'schema revision date')
      end
      if source_mtime == nil or
         (source_mtime.sec == compiled.source_mtime.sec and
          source_mtime.nsec == compiled.source_mtime.nsec) then
         return compiled.data
      end
   end

   local source = stream.open_input_byte_stream(filename)
   if binary.has_magic(source) then return load_compiled(source) end

   -- If the file doesn't have the magic, assume it's a source file.
   -- First, see if we compiled it previously and saved a compiled file
   -- in a well-known place.
   local compiled_filename = filename:gsub("%.conf$", "")..'.o'
   local source_mtime = {sec=source.mtime_sec, nsec=source.mtime_nsec}
   local compiled_stream = maybe(stream.open_input_byte_stream,
                                 compiled_filename)
   if compiled_stream then
      if binary.has_magic(compiled_stream) then
         log('loading compiled configuration from %s', compiled_filename)
         local conf = load_compiled(compiled_stream, source_mtime)
         if conf then
            log('compiled configuration %s is up to date.', compiled_filename)
            return conf
         end
         log('compiled configuration %s is out of date; recompiling.',
             compiled_filename)
      end
      compiled_stream:close()
   end

   -- Load and compile it.
   local source_str = source:read_string()
   source:close()
   log('loading source configuration from %s', filename)
   local conf = load_data_for_schema_by_name(opts.schema_name, source_str,
                                             filename)

   -- Save it, if we can.
   local success, err = pcall(binary.compile_data_for_schema_by_name,
                              opts.schema_name, conf, compiled_filename,
                              source_mtime)
   if not success then
      log('error saving compiled configuration %s: %s', compiled_filename, err)
   end

   -- Done.
   return conf
end

function selftest()
   print('selftest: lib.yang.yang')
   local tmp = os.tmpname()
   do
      local file = io.open(tmp, 'w')
      -- ietf-yang-types only defines types.  FIXME: use a schema that
      -- actually defines some data nodes.
      file:write('/* nothing */')
      file:close()
   end
   load_configuration(tmp, {schema_name='ietf-yang-types'})
   load_configuration(tmp, {schema_name='ietf-yang-types'})
   os.remove(tmp)
   load_configuration(tmp..'.o', {schema_name='ietf-yang-types'})
   os.remove(tmp..'.o')
   print('selftest: ok')
end
