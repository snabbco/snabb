-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local lib = require("core.lib")
local shm = require("core.shm")
local xpath = require("lib.yang.path")
local yang = require("lib.yang.yang")
local yang_data = require("lib.yang.data")
local counter = require("core.counter")

local counter_directory = "/apps"

local function flatten(val)
    local rtn = {}
    for k, v in pairs(val) do
        if type(v) == "table" then
            v = flatten(v)
            for k1, v1 in pairs(v) do rtn[k1] = v1 end
        else
            rtn[k] = v
        end
    end
    return rtn
end

local function find_counters(pid)
    local path = shm.root.."/"..pid..counter_directory
    local counters = {}
    for _, c in pairs(lib.files_in_directory(path)) do
        local counterdir = "/"..pid..counter_directory.."/"..c
        counters[c] = shm.open_frame(counterdir)
    end
    return counters
end

function collect_state_leaves(schema)
    -- Iterate over schema looking fo state leaves at a specific path into the
    -- schema. This should return a dictionary of leaf to lua path.
    local function collection(scm, path)
        local function newpath(oldpath)
            return lib.deepcopy(oldpath)
        end
        if path == nil then path = {} end
        table.insert(path, scm.id)

        if scm.kind == "container" then
            -- Iterate over the body and recursively call self on all children.
            local rtn = {}
            for _, child in pairs(scm.body) do
                local leaves = collection(child, newpath(path))
                table.insert(rtn, leaves)
            end
            return rtn
        elseif scm.kind == "leaf" then
            if scm.config == false then
                local rtn = {}
                rtn[path] = scm.id
                return rtn
            end
        elseif scm.kind == "module" then
            local rtn = {}
            for _, v in pairs(scm.body) do
                -- We deliberately don't want to include the module in the path.
                table.insert(rtn, collection(v, {}))
            end
            return rtn
        end
        return {}
    end

    local leaves = collection(schema)
    if leaves == nil then return {} end
    leaves = flatten(leaves)
    return function () return leaves end
end

local function set_data_value(data, path, value)
    local head = yang_data.normalize_id(table.remove(path, 1))
    if #path == 0 then
        data[head] = value
        return
    end
    if data[head] == nil then data[head] = {} end
    set_data_value(data[head], path, value)
end

function show_state(scm, pid, raw_path)
    local schema = yang.load_schema_by_name(scm)
    local grammar = yang_data.data_grammar_from_schema(schema)
    local counters = find_counters(pid)
    local path = xpath.convert_path(grammar, raw_path)

    -- Lookup the specific schema element that's being addressed by the path
    local leaves = collect_state_leaves(schema)()
    local data = {}
    for leaf_path, leaf in pairs(leaves) do
        for _, counter in pairs(counters) do
            if counter[leaf] then
                set_data_value(data, leaf_path, counter[leaf])
            end
        end
    end
    return data
end

function selftest ()
   print("selftest: lib.yang.state")
   local simple_router_schema_src = [[module snabb-simple-router {
      namespace snabb:simple-router;
      prefix simple-router;

      import ietf-inet-types {prefix inet;}

      leaf active { type boolean; default true; }
      leaf-list blocked-ips { type inet:ipv4-address; }

      container routes {
         presence true;
         list route {
            key addr;
            leaf addr { type inet:ipv4-address; mandatory true; }
            leaf port { type uint8 { range 0..11; } mandatory true; }
         }

      }



      container state {
         presence true;
         config false;

         leaf total-packets {
            type uint64 {
               default 0;
            }
         }

         leaf dropped-packets {
            type uint64 {
               default 0;
            }
         }
      }

      grouping detailed-counters {
         leaf dropped-wrong-route {
            type uint64 { default 0; }
         }
         leaf dropped-not-permitted {
            type uint64 { default 0; }
         }
      }

      container detailed-state {
         presence true;
         config false;
         uses "detailed-counters";
      }
   }]]
   local function table_length(tbl)
      local rtn = 0
      for k,v in pairs(tbl) do rtn = rtn + 1 end
      return rtn
   end
   local function in_array(needle, haystack)
      for _, i in pairs(haystack) do if needle == i then return true end end
      return false
   end

   local simple_router_schema = yang.load_schema(simple_router_schema_src,
      "state-test")
   local leaves = collect_state_leaves(simple_router_schema)()

   -- Check the correct number of leaves have been found
   assert(table_length(leaves) == 4)

   -- Check it's found every state path.
   local state_leaves = {
      "total-packets",
      "dropped-packets",
      "dropped-wrong-route",
      "dropped-not-permitted"
   }
   for _, leaf in pairs(leaves) do
      assert(in_array(leaf, state_leaves))
   end

   -- Check flatten produces a single dimentional table with all the elements.
   local multi_dimentional = {{hello="hello"}, {world="world"}}
   assert(flatten(multi_dimentional), {hello="hello", world="world"})
   print("selftest: ok")
end