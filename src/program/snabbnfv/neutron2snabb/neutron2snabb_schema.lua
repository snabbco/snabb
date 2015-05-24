-- neutron2snabb_schema: Scan mysqldump SQL files for schema informaion
module(..., package.seeall)

local lib = require("core.lib")

function read (directory, tables)
   local schema = {}
   for _, t in ipairs(tables) do
      schema[t] = columns(("%s/%s.sql"):format(directory, t))
   end
   return schema
end

-- Scan the order of keys from a table definition.


-- Return the columns of the named file in an array.
--
-- The array may containing extraneous trailing items but must give
-- the actual columns in order.
function columns (filename)
   -- Array of columns.
   local columns = {}
   local sql = lib.readfile(filename, '*a')
   local definition = sql:match("CREATE TABLE `[^`]*` (%b())")
   assert(definition, "failed to find CREATE TABLE definition")
   -- The expected table definition format is:
   --
   --   CREATE TABLE `ml2_port_bindings` (
   --     `port_id` varchar(36) NOT NULL,
   --     `host` varchar(255) NOT NULL,
   --     ...
   --   ) ...
   --
   -- We scan this and pick up the `identifiers`.
   definition:gsub("`([^`]*)`", function (id)
                      table.insert(columns, id)
   end)
   return columns
end

function selftest ()
   print("selftest: neutron2snabb_schema")
   local neutron2snabb = require("program.snabbnfv.neutron2snabb.neutron2snabb")
   -- Check that the schema we extract from the test database is
   -- compaible with the default schema. (That is expected for this
   -- particular data set.)
   local dir = "program/snabbnfv/test_fixtures/neutron_csv"
   local schema = read(dir, neutron2snabb.schema_tables)
   for tab, cols in pairs(neutron2snabb.default_schemas) do
      assert(schema[tab], "missing schema table: " .. tab)
      for i, col in ipairs(cols) do
         if schema[tab][i] ~= col then
            error(("Column mismatch: %s[%d] is %s (expected %s)"):format(
                  tab, i, schema[tab][i], col))
         end
      end
   end
   print("selftest: ok")
end

