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

    return lib.flatten(collection(schema))
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

local function show_state(pid, path)
    local counters = find_counters(pid)
    local mod, path = xpath.load_from_path(raw_path)
    local scm = yang.load_schema_by_name(mod)
    local leaves = collect_state_leaves(scm)
    local data = {}
    for leaf_path, leaf in pairs(leaves) do
        for _, counter in pairs(counters) do
            if counter[leaf] then
                set_data_value(data, leaf_path, counter[leaf])
            end
        end
    end
    local fakeout = util.FakeFile.new()
    yang_data.data_printer_from_schema(scm)(data, fakeout)
    return fakeout.contents
end