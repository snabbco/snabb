-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local lib = require("core.lib")
local shm = require("core.shm")
local xpath = require("lib.yang.xpath")
local yang = require("lib.yang.yang")
local yang_data = require("lib.yang.data")
local counter = require("core.counter")

local counter_directory = "/apps"

local function find_counters(pid)
    local path = shm.root.."/"..pid..counter_directory
    local counters = {}
    for _, c in pairs(lib.files_in_directory(path)) do
        local counterdir = "/"..pid..counter_directory.."/"..c
        counters[c] = shm.open_frame(counterdir)
    end
    return counters
end

local function flatten(t)
    local rtn = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            v = flatten(v)
            for k1, v1 in pairs(v) do rtn[k1] = v1 end
        else
            rtn[k] = v
        end
    end
    return rtn
end

function collect_state_leaves(schema)
    -- Iterate over schema looking fo state leaves at a specific path into the
    -- schema. This should return a dictionary of leaf to lua path.
    local function collection(scm, path, config)
        local function newpath(oldpath)
            return lib.deepcopy(oldpath)
        end
        if path == nil then path = {} end

        -- Add the current schema node to the path
        table.insert(path, scm.id)

        if scm.config ~= nil then
            config = scm.config
        end

        if scm.kind == "container" then
            -- Iterate over the body and recursively call self on all children.
            local rtn = {}
            for _, child in pairs(scm.body) do
                local leaves = collection(child, newpath(path), config)
                table.insert(rtn, leaves)
            end
            return rtn
        elseif scm.kind == "leaf" then
            if config == false then
                local rtn = {}
                rtn[path] = scm.id
                return rtn
            end
        elseif scm.kind == "module" then
            local rtn = {}
            for _, v in pairs(scm.body) do
                -- We deliberately don't want to include the module in the path.
                table.insert(rtn, collection(v, {}, config))
            end
            return rtn
        end
    end

    return flatten(collection(schema))
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

local function show_state(counters, scm, path)
    local leaves = collect_state_leaves(scm)
    local data = {}
    for leaf_path, leaf in pairs(leaves) do
        for _, counter in pairs(counters) do
            if counter[leaf] then
                set_data_value(data, leaf_path, counter[leaf])
            end
        end
    end
    yang_data.data_printer_from_schema(scm)(data, io.stdout)
end

local function show_usage(status)
    print(require("program.config.get_state.README_inc"))
    main.exit(status)
end

local function parse_args(args)
   local handlers = {}
   handlers.h = function() show_usage(0) end
   args = lib.dogetopt(args, handlers, "h", {help="h"})
   if #args ~= 2 then show_usage(1) end
   return unpack(args)
end

function run(args)
    local name, raw_path = parse_args(args)
    local mod, path = xpath.load_from_path(raw_path)

    -- Find the PID of the name.
    local pid = engine.enumerate_named_programs()[name]

    if pid == nil then
        error("No app found with the name '"..name.."'.")
    end

    local counters = find_counters(pid)
    local s = yang.load_schema_by_name(mod)

    show_state(counters, s, path)
end

function selftest()

end