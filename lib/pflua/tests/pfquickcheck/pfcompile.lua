#!/usr/bin/env luajit
module(..., package.seeall)

local backend = require("pf.backend")
local codegen = require("pf.codegen")

local use_native = os.getenv("PF_QUICKCHECK_NATIVE");

local function ast_to_ssa(ast)
   local convert_anf = require('pf.anf').convert_anf
   local convert_ssa = require('pf.ssa').convert_ssa
   return convert_ssa(convert_anf(ast))
end

-- Compile_lua_ast and compile_ast are a stable API for tests
-- The idea is to have various compile_* helpers that take a particular
-- stage of IR and compile accordingly, even as pflua internals change.
function compile_lua_ast(ast)
   -- Note: there isn't really a good result to return here for the
   --       native version since the asm doesn't really map to arithmetic
   --       expressions (see pflang_math.lua)
   return backend.emit_lua(ast_to_ssa(ast))
end

function compile_ast(ast, name)
   if not use_native then
      return backend.emit_and_load(ast_to_ssa(ast, name))
   else
      return codegen.load(ast_to_ssa(ast, name))
   end
end
