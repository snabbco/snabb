-- LuaJIT FII reflection library
-- License: Same as LuaJIT
-- Version: beta 1 (2012-06-02)
-- Author: Peter Cawley (lua@corsix.org)
local ffi = require "ffi"
local bit = require "bit"
local reflect = {}

-- Relevant minimal definitions from lj_ctype.h
ffi.cdef [[
  typedef struct CType {
    uint32_t info;
    uint32_t size;
    uint16_t sib;
    uint16_t next;
    uint32_t name;
  } CType;
  
  typedef struct CTState {
    CType *tab;
  } CTState;
]]

local function gc_str(gcref) -- Convert a GCref (to a GCstr) into a string
  if gcref ~= 0 then
    local ts = ffi.cast("uint32_t*", gcref)
    return ffi.string(ts + 4, ts[3])
  end
end

-- Acquire a pointer to this Lua universe's CTState
local CTState do
  -- Stripped down version of global_State from lj_obj.h.
  -- All that is needed is for the offset of the ctype_state field to be correct.
  local global_state_ptr = ffi.typeof [[
    struct {
      void* _; // strhash
      uint32_t _[2]; // strmask, strnum
      void(*_)(void); // allocf
      void* _; // allocd
      uint32_t _[14]; // gc
      char* _; // tmpbuf
      uint32_t _[28]; // tmpbuf, nilnode, strempty*, *mask, dispatchmode, mainthref, *tv*, uvhead, hookc*
      void(*_[3])(void); // hookf, wrapf, panic
      uint32_t _[5]; // vmstate, bc_*, jit_*
      uint32_t ctype_state;
    }*
  ]]
  local co = coroutine.create(function()end) -- Any live coroutine will do.
  local L = tonumber(tostring(co):match"%x*$", 16) -- Get the memory address of co's lua_State (ffi.cast won't accept a coroutine).
  local G = ffi.cast(global_state_ptr, ffi.cast("uint32_t*", L)[2])
  CTState = ffi.cast("CTState*", G.ctype_state)
end

-- Information for unpacking a `struct CType`.
-- One table per CT_* constant, containing:
-- * A name for that CT_
-- * Roles of the cid and size fields.
-- * Whether the sib field is meaningful.
-- * Zero or more applicable boolean flags.
local CTs = {[0] =
  {"int",
    "", "size", false,
    {0x08000000, "bool"},
    {0x04000000, "float", "subwhat"},
    {0x02000000, "const"},
    {0x01000000, "volatile"},
    {0x00800000, "unsigned"},
    {0x00400000, "long"},
  },
  {"struct",
    "", "size", true,
    {0x02000000, "const"},
    {0x01000000, "volatile"},
    {0x00800000, "union", "subwhat"},
    {0x00100000, "vla"},
  },
  {"ptr",
    "element_type", "size", false,
    {0x02000000, "const"},
    {0x01000000, "volatile"},
    {0x00800000, "ref", "subwhat"},
  },
  {"array",
    "element_type", "size", false,
    {0x08000000, "vector"},
    {0x04000000, "complex"},
    {0x02000000, "const"},
    {0x01000000, "volatile"},
    {0x00100000, "vla"},
  },
  {"void",
    "", "size", false,
    {0x02000000, "const"},
    {0x01000000, "volatile"},
  },
  {"enum",
    "type", "size", true,
  },
  {"func",
    "return_type", "nargs", true,
    {0x00800000, "vararg"},
    {0x00400000, "sse_reg_params"},
  },
  {"typedef", -- Not seen
    "element_type", "", false,
  },
  {"attrib", -- Only seen internally
    "type", "value", true,
  },
  {"field",
    "type", "offset", true,
  },
  {"bitfield",
    "", "offset", true,
    {0x08000000, "bool"},
    {0x02000000, "const"},
    {0x01000000, "volatile"},
    {0x00800000, "unsigned"},
  },
  {"constant",
    "type", "value", true,
    {0x02000000, "const"},
  },
  {"extern", -- Not seen
    "CID", "", true,
  },
  {"kw", -- Not seen
    "TOK", "size",
  },
}

-- Set of CType::cid roles which are a CTypeID.
local type_keys = {
  element_type = true,
  return_type = true,
  value_type = true,
  type = true,
}

-- Create a metatable for each CT.
local metatables = {
}
for _, CT in ipairs(CTs) do
  local what = CT[1]
  local mt = {__index = {}}
  metatables[what] = mt
end

-- Logic for merging an attribute CType onto the annotated CType.
local CTAs = {[0] =
  function(a, refct) error("TODO: CTA_NONE") end,
  function(a, refct) error("TODO: CTA_QUAL") end,
  function(a, refct)
    a = 2^a.value
    refct.alignment = a
    refct.attributes.align = a
  end,
  function(a, refct) refct.transparent = true end,
  function(a, refct) refct.sym_name = a.name end,
  function(a, refct) error("TODO: CTA_BAD") end,
}

-- C function calling conventions (CTCC_* constants in lj_refct.h)
local CTCCs = {[0] = 
  "cdecl",
  "thiscall",
  "fastcall",
  "stdcall",
}

local function refct_from_id(id) -- refct = refct_from_id(CTypeID)
  local ctype = CTState.tab[id]
  local CT_code = bit.rshift(ctype.info, 28)
  local CT = CTs[CT_code]
  local what = CT[1]
  local refct = setmetatable({
    what = what,
    typeid = id,
    name = gc_str(ctype.name),
  }, metatables[what])
  
  -- Interpret (most of) the CType::info field
  for i = 5, #CT do
    if bit.band(ctype.info, CT[i][1]) ~= 0 then
      if CT[i][3] == "subwhat" then
        refct.what = CT[i][2]
      else
        refct[CT[i][2]] = true
      end
    end
  end
  if CT_code <= 5 then
    refct.alignment = bit.lshift(1, bit.band(bit.rshift(ctype.info, 16), 15))
  elseif what == "func" then
    refct.convention = CTCCs[bit.band(bit.rshift(ctype.info, 16), 3)]
  end
  
  if CT[2] ~= "" then -- Interpret the CType::cid field
    local k = CT[2]
    local cid = bit.band(ctype.info, 0xffff)
    if type_keys[k] then
      if cid == 0 then
        cid = nil
      else
        cid = refct_from_id(cid)
      end
    end
    refct[k] = cid
  end
  
  if CT[3] ~= "" then -- Interpret the CType::size field
    local k = CT[3]
    refct[k] = ctype.size
    if k == "size" and bit.bnot(refct[k]) == 0 then
      refct[k] = "none"
    end
  end
  
  if what == "attrib" then
    -- Merge leading attributes onto the type being decorated.
    local CTA = CTAs[bit.band(bit.rshift(ctype.info, 16), 0xff)]
    if refct.type then
      local ct = refct.type
      ct.attributes = {}
      CTA(refct, ct)
      ct.typeid = refct.typeid
      refct = ct
    else
      refct.CTA = CTA
    end
  elseif what == "bitfield" then
    -- Decode extra bitfield fields, and make it look like a normal field.
    refct.offset = refct.offset + bit.band(ctype.info, 127) / 8
    refct.size = bit.band(bit.rshift(ctype.info, 8), 127) / 8
    refct.type = {
      what = "int",
      bool = refct.bool,
      const = refct.const,
      volatile = refct.volatile,
      unsigned = refct.unsigned,
      size = bit.band(bit.rshift(ctype.info, 16), 127),
    }
    refct.bool, refct.const, refct.volatile, refct.unsigned = nil
  end
  
  if CT[4] then -- Merge sibling attributes onto this type.
    while ctype.sib ~= 0 do
      local entry = CTState.tab[ctype.sib]
      if CTs[bit.rshift(entry.info, 28)][1] ~= "attrib" then break end
      if bit.band(entry.info, 0xffff) ~= 0 then break end
      local sib = refct_from_id(ctype.sib)
      sib:CTA(refct)
      ctype = entry
    end
  end
  
  return refct
end

local function sib_iter(s, refct)
  repeat
    local ctype = CTState.tab[refct.typeid]
    if ctype.sib == 0 then return end
    refct = refct_from_id(ctype.sib)
  until refct.what ~= "attrib" -- Pure attribs are skipped.
  return refct
end

local function siblings(refct)
  -- Follow to the end of the attrib chain, if any.
  while refct.attributes do
    refct = refct_from_id(CTState.tab[refct.typeid].sib)
  end

  return sib_iter, nil, refct
end

metatables.struct.__index.members = siblings
metatables.func.__index.arguments = siblings
metatables.enum.__index.values = siblings

local function find_sibling(refct, name)
  local num = tonumber(name)
  if num then
    for sib in siblings(refct) do
      if num == 1 then
        return sib
      end
      num = num - 1
    end
  else
    for sib in siblings(refct) do
      if sib.name == name then
        return sib
      end
    end
  end
end

metatables.struct.__index.member = find_sibling
metatables.func.__index.argument = find_sibling
metatables.enum.__index.value = find_sibling

function reflect.typeof(x) -- refct = reflect.typeof(ct)
  return refct_from_id(tonumber(ffi.typeof(x)))
end

return reflect
