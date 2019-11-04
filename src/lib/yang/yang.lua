-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local lib = require("core.lib")
local schema = require("lib.yang.schema")
local data = require("lib.yang.data")
local binary = require("lib.yang.binary")
local file = require("lib.stream.file")
local path_data = require("lib.yang.path_data")

load_schema = schema.load_schema
load_schema_file = schema.load_schema_file
load_schema_by_name = schema.load_schema_by_name

add_schema = schema.add_schema
add_schema_file = schema.add_schema_file

function load_config_for_schema (schema, stream)
   local data = data.load_config_for_schema(schema, stream)
   path_data.consistency_checker_from_schema(schema, true)(data)
   return data
end
function load_config_for_schema_by_name(schema_name, stream)
   local data = data.load_config_for_schema_by_name(schema_name, stream)
   path_data.consistency_checker_from_schema_by_name(schema_name, true)(data)
   return data
end

print_config_for_schema = data.print_config_for_schema
print_config_for_schema_by_name = data.print_config_for_schema_by_name

compile_config_for_schema = binary.compile_config_for_schema
compile_config_for_schema_by_name = binary.compile_config_for_schema_by_name

load_compiled_data_file = binary.load_compiled_data_file

local params = {
   verbose = {},
   schema_name = {required=true},
   revision_date = {},
   compiled_filename = {},
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
      local ok, result = pcall(binary.load_compiled_data, stream)
      if not ok then
         log('failed to load compiled configuration: %s', tostring(result))
         return
      end
      local compiled = result
      local expected_revision = opts.revision_date or
         load_schema_by_name(opts.schema_name).last_revision
      if opts.schema_name ~= compiled.schema_name then
         log('expected schema name %s in compiled file, but got %s',
             opts.schema_name, compiled.schema_name)
         return
      end
      if expected_revision ~= compiled.revision_date then
         log('expected schema revision date %s in compiled file, but got "%s"',
             expected_revision, compiled.revision_date)
         return
      else
      end
      if source_mtime then
         if (source_mtime.sec == compiled.source_mtime.sec and
             source_mtime.nsec == compiled.source_mtime.nsec) then
            log('compiled configuration is up to date.')
            return compiled.data
         end
         log('compiled configuration is out of date; recompiling.')
         return
      end
      -- No source file.
      log('loaded compiled configuration with no corresponding source file.')
      return compiled.data
   end

   local source = assert(file.open(filename))
   if binary.has_magic(source) then
      local conf = load_compiled(source)
      if conf then return conf end
   end

   -- If the file doesn't have the magic, assume it's a source file.
   -- First, see if we compiled it previously and saved a compiled file
   -- in a well-known place.
   local stat = source.io.fd:stat()
   local source_mtime = { sec=stat.st_mtime, nsec=stat.st_mtime_nsec }
   local compiled_filename = opts.compiled_filename
   if not compiled_filename then
      compiled_filename = filename:gsub("%.conf$", "")..'.o'
   end
   local use_compiled_cache = not lib.getenv("SNABB_RANDOM_SEED")
   local compiled_stream = maybe(file.open, compiled_filename)
   if compiled_stream then
      if binary.has_magic(compiled_stream) and use_compiled_cache then
         log('loading compiled configuration from %s', compiled_filename)
         local conf = load_compiled(compiled_stream, source_mtime)
         if conf then return conf end
      end
      compiled_stream:close()
   end

   -- Load and compile it.
   log('loading source configuration')
   local conf = load_config_for_schema_by_name(opts.schema_name, source)
   if use_compiled_cache then
      -- Save it, if we can.
      local success, err = pcall(binary.compile_config_for_schema_by_name,
                                 opts.schema_name, conf, compiled_filename,
                                 source_mtime)
      if success then
         log('wrote compiled configuration %s', compiled_filename)
      else
         log('error saving compiled configuration %s: %s', compiled_filename, err)
      end
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
