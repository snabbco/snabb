module(...,package.seeall)

local utils = require('pf.utils')

local verbose = os.getenv("PF_VERBOSE");

local set, pp = utils.set, utils.pp

local relop_map = {
   ['<']='<', ['<=']='<=', ['=']='==', ['!=']='~=', ['>=']='>=', ['>']='>'
}

local relop_inversions = {
   ['<']='>=', ['<=']='>', ['=']='!=', ['!=']='=', ['>=']='<', ['>']='<='
}

local simple_results = set('true', 'false', 'call')

local function invert_bool(expr)
   if expr[1] == 'true' then return { 'false' } end
   if expr[1] == 'false' then return { 'true' } end
   assert(relop_inversions[expr[1]])
   return { relop_inversions[expr[1]], expr[2], expr[3] }
end

local function is_simple_expr(expr)
   -- Simple := return true | return false | return call | goto Label
   if expr[1] == 'return' then return simple_results[expr[2][1]] end
   return expr[1] == 'goto'
end

-- Lua := Do | Return | Goto | If | Bind | Label
-- Do := 'do' Lua+
-- Return := 'return' Bool|Call
-- Goto := 'goto' Label
-- If := 'if' Bool Lua Lua?
-- Bind := 'bind' Name Expr
-- Label := 'label' Lua
local function residualize_lua(program)
   -- write blocks, scope is dominator tree
   local function nest(block, result, knext)
      for _, binding in ipairs(block.bindings) do
         table.insert(result, { 'bind', binding.name, binding.value })
      end
      local control = block.control
      if control[1] == 'goto' then
         local succ = program.blocks[control[2]]
         if succ.idom == block.label then
            nest(succ, result)
         else
            table.insert(result, control)
         end
      elseif control[1] == 'return' then
         table.insert(result, control)
      else
         assert(control[1] == 'if')
         local test, t_label, f_label = control[2], control[3], control[4]
         local t_block, f_block = program.blocks[t_label], program.blocks[f_label]
         local expr = { 'if', test, { 'do' }, { 'do' } }
         -- First, add the test.
         table.insert(result, expr)
         -- Then fill in the nested then and else arms, if they have no
         -- other predecessors.
         if #t_block.preds == 1 then
            assert(t_block.idom == block.label)
            nest(t_block, expr[3])
         else
            table.insert(expr[3], { 'goto', t_label })
         end
         if #f_block.preds == 1 then
            assert(f_block.idom == block.label)
            nest(f_block, expr[4])
         else
            table.insert(expr[4], { 'goto', f_label })
         end
         -- Finally add immediately dominated blocks, with labels.  We
         -- only have to do this in "if" blocks because "return" blocks
         -- have no successors, and "goto" blocks do not immediately
         -- dominate blocks that are not their successors.
         for _,label in ipairs(block.doms) do
            local dom_block = program.blocks[label]
            if #dom_block.preds ~= 1 then
               local wrap = { 'label', label, { 'do' } }
               table.insert(result, wrap)
               nest(dom_block, wrap[3])
            end
         end
      end
   end
   local result = { 'do' }
   nest(program.blocks[program.start], result, nil)
   return result
end

-- Lua := Do | Return | Goto | If | Bind | Label
-- Do := 'do' Lua+
-- Return := 'return' Bool|Call
-- Goto := 'goto' Label
-- If := 'if' Bool Lua Lua?
-- Bind := 'bind' Name Expr
-- Label := 'label' Lua
local function cleanup(expr, is_last)
   local function splice_tail(result, expr)
      if expr[1] == 'do' then
         -- Splice a tail "do" into the parent do.
         for j=2,#expr do
            if j==#expr then
               splice_tail(result, expr[j])
            else
               table.insert(result, expr[j])
            end
         end
         return
      elseif expr[1] == 'if' then
         if expr[3][1] == 'return' or expr[3][1] == 'goto' then
            -- Splice the consequent of a tail "if" into the parent do.
            table.insert(result, { 'if', expr[2], expr[3] })
            if expr[4] then splice_tail(result, expr[4]) end
            return
         end
      elseif expr[1] == 'label' then
         -- Likewise, try to splice the body of a tail labelled
         -- statement.
         local tail = { 'do' }
         splice_tail(tail, expr[3])
         if #tail > 2 then
            table.insert(result, { 'label', expr[2], tail[2] })
            for i=3,#tail do table.insert(result, tail[i]) end
            return
         end
      end
      table.insert(result, expr)
   end
   local op = expr[1]
   if op == 'do' then
      if #expr == 2 then return cleanup(expr[2], is_last) end
      local result = { 'do' }
      for i=2,#expr do
         local subexpr = cleanup(expr[i], i==#expr)
         if i==#expr then
            splice_tail(result, subexpr)
         else
            table.insert(result, subexpr)
         end
      end
      return result
   elseif op == 'return' then
      return expr
   elseif op == 'goto' then
      return expr
   elseif op == 'if' then
      local test, t, f = expr[2], cleanup(expr[3], true), cleanup(expr[4], true)
      if not is_simple_expr(t) and is_simple_expr(f) then
         test, t, f = invert_bool(test), f, t
      end
      if is_simple_expr(t) and is_last then
         local result = { 'do', { 'if', test, t } }
         splice_tail(result, f)
         return result
      else
         return { 'if', test, t, f }
      end
   elseif op == 'bind' then
      return expr
   else
      assert (op == 'label')
      return { 'label', expr[2], cleanup(expr[3], is_last) }
   end
end

local function filter_builder(...)
   -- Reserve first part for libraries.
   local parts = {'', 'return function('}
   local nparts = 2
   local indent = ''
   local libraries = {}
   local builder = {}
   function builder.write(str)
      nparts = nparts + 1
      parts[nparts] = str
   end
   function builder.writeln(str)
      builder.write(indent .. str .. '\n')
   end
   function builder.bind(var, val)
      builder.writeln('local '..var..' = '..val)
   end
   function builder.push()
      indent = indent .. '   '
   end
   function builder.else_()
      builder.write(indent:sub(4) .. 'else\n')
   end
   function builder.pop()
      indent = indent:sub(4)
      builder.writeln('end')
   end
   function builder.jump(label)
      builder.writeln('goto '..label)
   end
   function builder.writelabel(label)
      builder.write('::'..label..'::\n')
   end
   function builder.c(str)
      local lib, func = str:match('([a-z]+).([a-z]+)')
      if libraries[str] then return func end
      libraries[str] = 'local '..func..' = require("'..lib..'").'..func
      return func
   end
   function builder.header()
      for _,library in pairs(libraries) do
         parts[1] = library.."\n"..parts[1]
      end
   end
   function builder.finish()
      builder.pop()
      builder.header()
      local written = table.concat(parts)
      if verbose then print(written) end
      return written
   end
   local needs_comma = false
   for _, v in ipairs({...}) do
      if needs_comma then builder.write(',') end
      builder.write(v)
      needs_comma = true
   end
   builder.write(')\n')
   builder.push()
   return builder
end

local function read_buffer_word_by_type(builder, buffer, offset, size)
   if size == 1 then
      return buffer..'['..offset..']'
   elseif size == 2 then
      return builder.c('ffi.cast')..'("uint16_t*", '..buffer..'+'..offset..')[0]'
   elseif size == 4 then
      return (builder.c('ffi.cast')..'("uint32_t*", '..buffer..'+'..offset..')[0]')
   else
      error("bad [] size: "..size)
   end
end

local function serialize(builder, stmt)
   local function serialize_value(expr)
      if expr == 'len' then return 'length' end
      if type(expr) == 'number' then return expr end
      if type(expr) == 'string' then return expr end
      assert(type(expr) == 'table', 'unexpected type '..type(expr))
      local op, lhs = expr[1], serialize_value(expr[2])
      if op == 'ntohs' then return builder.c('bit.rshift')..'('..builder.c('bit.bswap')..'('..lhs..'), 16)'
      elseif op == 'ntohl' then return builder.c('bit.bswap')..'('..lhs..')'
      elseif op == 'int32' then return builder.c('bit.tobit')..'('..lhs..')'
      elseif op == 'uint32' then return '('..lhs..' % '.. 2^32 ..')'
      end
      local rhs = serialize_value(expr[3])
      if op == '[]' then
         return read_buffer_word_by_type(builder, 'P', lhs, rhs)
      elseif op == '+' then return '('..lhs..' + '..rhs..')'
      elseif op == '-' then return '('..lhs..' - '..rhs..')'
      elseif op == '*' then return '('..lhs..' * '..rhs..')'
      elseif op == '*64' then
         return 'tonumber(('..lhs..' * 1LL * '..rhs..') % '.. 2^32 ..')'
      elseif op == '/' then return builder.c('math.floor')..'('..lhs..' / '..rhs..')'
      elseif op == '&' then return builder.c('bit.band')..'('..lhs..','..rhs..')'
      elseif op == '^' then return builder.c('bit.bxor')..'('..lhs..','..rhs..')'
      elseif op == '|' then return builder.c('bit.bor')..'('..lhs..','..rhs..')'
      elseif op == '<<' then return builder.c('bit.lshift')..'('..lhs..','..rhs..')'
      elseif op == '>>' then return builder.c('bit.rshift')..'('..lhs..','..rhs..')'
      else error('unexpected op', op) end
   end

   local function serialize_bool(expr)
      local op = expr[1]
      if op == 'true' then
         return 'true'
      elseif op == 'false' then
         return 'false'
      elseif relop_map[op] then
         -- An arithmetic relop.
         local op = relop_map[op]
         local lhs, rhs = serialize_value(expr[2]), serialize_value(expr[3])
         return lhs..' '..op..' '..rhs
      else
         error('unhandled primitive'..op)
      end
   end

   local function serialize_call(expr)
      local args = { 'P', 'len' }
      for i=3,#expr do table.insert(args, serialize_value(expr[i])) end
      return 'self.'..expr[2]..'('..table.concat(args, ', ')..')'
   end

   local serialize_statement

   local function serialize_sequence(stmts)
      if stmts[1] == 'do' then
         for i=2,#stmts do serialize_statement(stmts[i], i==#stmts) end
      else
         serialize_statement(stmts, true)
      end
   end

   function serialize_statement(stmt, is_last)
      local op = stmt[1]
      if op == 'do' then
         builder.writeln('do')
         builder.push()
         serialize_sequence(stmt)
         builder.pop()
      elseif op == 'return' then
         if not is_last then
            return serialize_statement({ 'do', stmt }, false)
         end
         if stmt[2][1] == 'call' then
            builder.writeln('return '..serialize_call(stmt[2]))
         else
            builder.writeln('return '..serialize_bool(stmt[2]))
         end
      elseif op == 'goto' then
         builder.jump(stmt[2])
      elseif op == 'if' then
         local test, t, f = stmt[2], stmt[3], stmt[4]
         local test_str = 'if '..serialize_bool(test)..' then'
         if is_simple_expr(t) then
            if t[1] == 'return' then
               local result
               if t[2][1] == 'call' then result = serialize_call(t[2])
               else result = serialize_bool(t[2]) end
               builder.writeln(test_str..' return '..result..' end')
            else
               assert(t[1] == 'goto')
               builder.writeln(test_str..' goto '..t[2]..' end')
            end
            if f then serialize_statement(f, is_last) end
         else
            builder.writeln(test_str)
            builder.push()
            serialize_sequence(t)
            if f then
               builder.else_()
               serialize_sequence(f)
            end
            builder.pop()
         end
      elseif op == 'bind' then
         builder.bind(stmt[2], serialize_value(stmt[3]))
      else
         assert(op == 'label')
         builder.writelabel(stmt[2])
         serialize_statement(stmt[3], is_last)
      end
   end
   serialize_sequence(stmt)
end

function emit_lua(ssa)
   local builder = filter_builder('P', 'length')
   serialize(builder, cleanup(residualize_lua(ssa), true))
   local str = builder.finish()
   if verbose then pp(str) end
   return str
end

function emit_match_lua(ssa)
   local builder = filter_builder('self', 'P', 'length')
   serialize(builder, cleanup(residualize_lua(ssa), true))
   local str = builder.finish()
   if verbose then pp(str) end
   return str
end

function emit_and_load(ssa, name)
   return assert(loadstring(emit_lua(ssa), name))()
end

function emit_and_load_match(ssa, name)
   return assert(loadstring(emit_match_lua(ssa), name))()
end

function selftest()
   print("selftest: pf.backend")
   local parse = require('pf.parse').parse
   local expand = require('pf.expand').expand
   local optimize = require('pf.optimize').optimize
   local convert_anf = require('pf.anf').convert_anf
   local convert_ssa = require('pf.ssa').convert_ssa

   local function test(expr)
      local ast = optimize(expand(parse(expr), "EN10MB"))
      return emit_and_load(convert_ssa(convert_anf(ast)))
   end

   test("tcp port 80 or udp port 34")
   print("OK")
end
