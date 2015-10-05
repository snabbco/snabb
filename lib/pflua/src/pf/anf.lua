module(...,package.seeall)

local utils = require('pf.utils')

local set, pp, dup = utils.set, utils.pp, utils.dup

local relops = set('<', '<=', '=', '!=', '>=', '>')

local binops = set(
   '+', '-', '*', '*64', '/', '&', '|', '^', '<<', '>>'
)
local unops = set('ntohs', 'ntohl', 'uint32', 'int32')

local simple = set('true', 'false', 'match', 'fail')

local count = 0

local function fresh()
   count = count + 1
   return 'var'..count
end

local function lower_arith(expr, k)
   if type(expr) ~= 'table' then return k(expr) end
   local op = expr[1]
   if unops[op] then
      local operand = expr[2]
      local function have_operand(operand)
         local result = fresh()
         return { 'let', result, { op, operand }, k(result) }
      end
      return lower_arith(operand, have_operand)
   elseif binops[op] then
      local lhs, rhs = expr[2], expr[3]
      local function have_lhs(lhs)
         local function have_rhs(rhs)
            local result = fresh()
            return { 'let', result, { op, lhs, rhs}, k(result) }
         end
         return lower_arith(rhs, have_rhs)
      end
      return lower_arith(lhs, have_lhs)
   else
      assert(op == '[]')
      local operand, size = expr[2], expr[3]
      local function have_operand(operand)
         local result = fresh()
         return { 'let', result, { op, operand, size }, k(result) }
      end
      return lower_arith(operand, have_operand)
   end
end

local function lower_comparison(expr, k)
   local op, lhs, rhs = expr[1], expr[2], expr[3]
   assert(relops[op])
   local function have_lhs(lhs)
      local function have_rhs(rhs)
         return k({ op, lhs, rhs })
      end
      return lower_arith(rhs, have_rhs)
   end
   return lower_arith(lhs, have_lhs)
end

local function lower_bool(expr, k)
   local function lower(expr)
      local function have_bool(expr)
         return expr
      end
      return lower_bool(expr, have_bool)
   end
   local op = expr[1]
   if op == 'if' then
      local test, t, f = expr[2], expr[3], expr[4]
      local function have_test(test)
         return k({ 'if', test, lower(t), lower(f) })
      end
      return lower_bool(test, have_test)
   elseif simple[op] then
      return k(expr)
   elseif op == 'call' then
      local out = { 'call', expr[2] }
      local function lower_arg(i)
         if i > #expr then return k(out) end
         local function have_arg(arg)
            out[i] = arg
            return lower_arg(i + 1)
         end
         return lower_arith(expr[i], have_arg)
      end
      return lower_arg(3)
   else
      return lower_comparison(expr, k)
   end
end

local function lower(expr)
   count = 0
   local function have_bool(expr)
      return expr
   end
   return lower_bool(expr, have_bool)
end

local function cse(expr)
   local replacements = {}
   local function lookup(expr)
      return replacements[expr] or expr 
   end
   local function visit(expr, env)
      if type(expr) == 'number' then return expr end
      if type(expr) == 'string' then return lookup(expr) end
      local op = expr[1]
      if op == 'let' then
         local var, val, body = expr[2], expr[3], expr[4]
         assert(type(val) == 'table')
         local arith_op = val[1]
         local key, replacement_val
         if unops[arith_op] then
            local lhs = visit(val[2], env)
            key = arith_op..','..lhs
            replacement_val = { arith_op, lhs }
         elseif binops[arith_op] then
            local lhs, rhs = visit(val[2], env), visit(val[3], env)
            key = arith_op..','..lhs..','..rhs
            replacement_val = { arith_op, lhs, rhs }
         else
            assert(arith_op == '[]')
            local lhs, size = visit(val[2], env), val[3]
            key = arith_op..','..lhs..','..size
            replacement_val = { arith_op, lhs, size }
         end
         local cse_var = env[key]
         if cse_var then
            replacements[var] = cse_var
            return visit(body, env)
         else
            env = dup(env)
            env[key] = var
            return { 'let', var, replacement_val, visit(body, env) }
         end
      elseif op == 'if' then
         return { 'if', visit(expr[2], env), visit(expr[3], env), visit(expr[4], env) }
      elseif simple[op] then
         return expr
      elseif op == 'call' then
         local out = { 'call', expr[2] }
         for i=3,#expr do table.insert(out, visit(expr[i], env)) end
         return out
      else
         assert(relops[op])
         return { op, visit(expr[2], env), visit(expr[3], env) }
      end
   end
   return visit(expr, {})
end

local function inline_single_use_variables(expr)
   local counts, substs = {}, {}
   local function count(expr)
      if expr == 'len' then return
      elseif type(expr) == 'number' then return
      elseif type(expr) == 'string' then counts[expr] = counts[expr] + 1 
      else
         assert(type(expr) == 'table')
         local op = expr[1]
         if op == 'if' then
            count(expr[2])
            count(expr[3])
            count(expr[4])
         elseif op == 'let' then
            counts[expr[2]] = 0
            count(expr[3])
            count(expr[4])
         elseif relops[op] then
            count(expr[2])
            count(expr[3])
         elseif unops[op] then
            count(expr[2])
         elseif binops[op] then
            count(expr[2])
            count(expr[3])
         elseif simple[op] then

         elseif op == 'call' then
            for i=3,#expr do count(expr[i]) end
         else 
            assert(op == '[]')
            count(expr[2])
         end
      end
   end
   local function lookup(expr)
      return substs[expr] or expr
   end
   local function subst(expr) 
      if type(expr) == 'number' then return expr end
      if type(expr) == 'string' then return lookup(expr) end
      local op = expr[1]
      if op == 'let' then
         local var, val, body = expr[2], expr[3], expr[4]
         assert(type(val) == 'table')
         local arith_op = val[1]
         local replacement_val
         if unops[arith_op] then
            local lhs = subst(val[2])
            replacement_val = { arith_op, lhs }
         elseif binops[arith_op] then
            local lhs, rhs = subst(val[2]), subst(val[3])
            replacement_val = { arith_op, lhs, rhs }
         else
            assert(arith_op == '[]')
            local lhs, size = subst(val[2]), val[3]
            replacement_val = { arith_op, lhs, size }
         end
         if counts[var] == 1 then
            substs[var] = replacement_val
            return subst(body)
         else
            return { 'let', var, replacement_val, subst(body) }
         end
      elseif op == 'if' then
         return { 'if', subst(expr[2]), subst(expr[3]), subst(expr[4]) }
      elseif simple[op] then
         return expr
      elseif op == 'call' then
         local out = { 'call', expr[2] }
         for i=3,#expr do table.insert(out, subst(expr[i])) end
         return out
      else
         assert(relops[op])
         return { op, subst(expr[2]), subst(expr[3]) }
      end
   end
   count(expr)
   return subst(expr)
end

local function renumber(expr)
   local count, substs = 0, {}
   local function intern(var)
      count = count + 1
      local fresh = 'v'..count
      substs[var] = fresh
      return fresh
   end
   local function lookup(var)
      if var == 'len' then return var end
      return assert(substs[var], "unbound variable: "..var)
   end
   local function visit(expr)
      if type(expr) == 'number' then return expr end
      if type(expr) == 'string' then return lookup(expr) end
      local op = expr[1]
      if op == 'let' then
         local var, val, body = expr[2], expr[3], expr[4]
         local fresh = intern(var)
         return { 'let', fresh, visit(val), visit(body) }
      elseif op == 'if' then
         return { 'if', visit(expr[2]), visit(expr[3]), visit(expr[4]) }
      elseif simple[op] then
         return expr
      elseif op == 'call' then
         local out = { 'call', expr[2] }
         for i=3,#expr do table.insert(out, visit(expr[i])) end
         return out
      elseif relops[op] then
         return { op, visit(expr[2]), visit(expr[3]) }
      elseif unops[op] then
         return { op, visit(expr[2]) }
      elseif binops[op] then
         return { op, visit(expr[2]), visit(expr[3]) }
      else
         assert(op == '[]')
         return { op, visit(expr[2]), expr[3] }
      end
   end
   return visit(expr)
end

function convert_anf(expr)
   return renumber(inline_single_use_variables(cse(lower(expr))))
end

function selftest()
   local parse = require('pf.parse').parse
   local expand = require('pf.expand').expand
   local optimize = require('pf.optimize').optimize
   local function test(expr)
      return convert_anf(optimize(expand(parse(expr), "EN10MB")))
   end
   print("selftest: pf.anf")
   test("tcp port 80")
   print("OK")
end
