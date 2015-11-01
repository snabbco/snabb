module(...,package.seeall)

local utils = require('pf.utils')

local verbose = os.getenv("PF_VERBOSE");

local set, pp, dup, concat = utils.set, utils.pp, utils.dup, utils.concat

local relops = set('<', '<=', '=', '!=', '>=', '>')

--- SSA := { start=Label, blocks={Label=>Block, ...} }
--- Label := string
--- Block := { label=Label, bindings=[{name=Var, value=Expr},...], control=Control }
--- Expr := UnaryOp | BinaryOp | PacketAccess
--- Control := ['return', Bool|Call] | ['if', Bool, Label, Label] | ['goto',Label]
--- Bool := true | false | Comparison

local function print_ssa(ssa)
   local function block_repr(block)
      local bindings = { 'bindings' }
      for _,binding in ipairs(block.bindings) do
         table.insert(bindings, { binding.name, binding.value })
      end
      return { 'block',
               { 'label', block.label },
               bindings,
               { 'control', block.control } }
   end
   local blocks = { 'blocks' }
   if ssa.order then
      for order,label in ipairs(ssa.order) do
         table.insert(blocks, block_repr(ssa.blocks[label]))
      end
   else
      for label,block in pairs(ssa.blocks) do
         table.insert(blocks, block_repr(block))
      end
   end
   pp({ 'ssa', { 'start', ssa.start }, blocks })
   return ssa
end

local function lower(expr)
   local label_counter = 0
   local ssa = { blocks = {} }
   local function add_block()
      label_counter = label_counter + 1
      local label = 'L'..label_counter
      local block = { bindings={}, label=label }
      ssa.blocks[label] = block
      return block
   end
   local function finish_return(block, bool)
      block.control = { 'return', bool }
   end
   local function finish_if(block, bool, kt, kf)
      block.control = { 'if', bool, kt.label, kf.label }
   end
   local function finish_goto(block, k)
      block.control = { 'goto', k.label }
   end
   local function compile_bool(expr, block, kt, kf)
      assert(type(expr) == 'table')
      local op = expr[1]
      if op == 'if' then
         local kthen, kelse = add_block(), add_block()
         compile_bool(expr[2], block, kthen, kelse)
         compile_bool(expr[3], kthen, kt, kf)
         compile_bool(expr[4], kelse, kt, kf)
      elseif op == 'let' then
         local name, value, body = expr[2], expr[3], expr[4]
         table.insert(block.bindings, { name=name, value=value })
         compile_bool(body, block, kt, kf)
      elseif op == 'true' then
         finish_goto(block, kt)
      elseif op == 'false' then
         finish_goto(block, kf)
      elseif op == 'match' then
         finish_return(block, { 'true' })
      elseif op == 'fail' then
         finish_return(block, { 'false' })
      elseif op == 'call' then
         finish_return(block, expr)
      else
         assert(relops[op])
         finish_if(block, expr, kt, kf)
      end
   end
   local start, accept, reject = add_block(), add_block(), add_block()
   compile_bool(expr, start, accept, reject)
   finish_return(accept, { 'true' })
   finish_return(reject, { 'false' })
   ssa.start = start.label
   return ssa
end

local function compute_use_counts(ssa)
   local result = {}
   local visited = {}
   local function visit(label)
      result[label] = result[label] + 1
      if not visited[label] then
         visited[label] = true
         local block = ssa.blocks[label]
         if block.control[1] == 'if' then
            visit(block.control[3])
            visit(block.control[4])
         elseif block.control[1] == 'goto' then
            visit(block.control[2])
         else
            assert(block.control[1] == 'return')
            -- Nothing to do.
         end
      end
   end
   for label,_ in pairs(ssa.blocks) do result[label] = 0 end
   visit(ssa.start)
   return result
end

local relop_inversions = {
   ['<']='>=', ['<=']='>', ['=']='!=', ['!=']='=', ['>=']='<', ['>']='<='
}

local function invert_bool(expr)
   if expr[1] == 'true' then return { 'false' } end
   if expr[1] == 'false' then return { 'true' } end
   assert(relop_inversions[expr[1]])
   return { relop_inversions[expr[1]], expr[2], expr[3] }
end

local function is_simple_expr(expr)
   -- Simple := return true | return false | goto Label
   if expr[1] == 'return' then
      return expr[2][1] == 'true' or expr[2][1] == 'false'
   end
   return expr[1] == 'goto'
end

local function is_simple_block(block)
   -- Simple := return true | return false | goto Label
   if #block.bindings ~= 0 then return nil end
   return is_simple_expr(block.control)
end

local function simplify(ssa)
   local result = { start=ssa.start, blocks={} }
   local use_counts = compute_use_counts(ssa)
   local function visit(label)
      if result.blocks[label] then return result.blocks[label] end
      local block = dup(ssa.blocks[label])
      if block.control[1] == 'if' then
         local t, f = visit(block.control[3]), visit(block.control[4])
         if (is_simple_block(t) and is_simple_block(f) and
             t.control[1] == 'return' and f.control[1] == 'return') then
            local t_val, f_val = t.control[2][1], f.control[2][1]
            if t_val == f_val then
               -- if EXP then return true else return true end -> return true
               --
               -- This is valid because EXP can have no side effects and
               -- has no control effect.
               block.control = t.control
            elseif t_val == 'true' and f_val == 'false' then
               -- if EXP then return true else return false -> return EXP
               block.control = { 'return', block.control[2] }
            else
               assert(t_val == 'false' and f_val == 'true')
               -- if EXP then return false else return true -> return not EXP
               block.control = { 'return', invert_bool(block.control[2]) }
            end
         else
            local control = { 'if', block.control[2], t.label, f.label }
            if t.control[1] == 'goto' and #t.bindings == 0 then
               control[3] = t.control[2]
            end
            if f.control[1] == 'goto' and #f.bindings == 0 then
               control[4] = f.control[2]
            end
            block.control = control
         end
      elseif block.control[1] == 'goto' then
         local k = visit(block.control[2])
         -- Inline blocks in cases where the inlining will not increase
         -- code size, which is when the successor is simple (and thus
         -- can be copied) or if the successor only has one predecessor.
         if is_simple_block(k) or use_counts[block.control[2]] == 1 then
            block.bindings = concat(block.bindings, k.bindings)
            block.control = k.control
            -- A subsequent iteration will remove the unused "k" block.
         end
      else
         assert(block.control[1] == 'return')
         -- Nothing to do.
      end
      result.blocks[label] = block
      return block
   end
   visit(ssa.start)
   return result
end

local function optimize_ssa(ssa)
   ssa = utils.fixpoint(simplify, ssa)
   if verbose then pp(ssa) end
   return ssa
end

-- Compute a reverse-post-order sort of the blocks, which is a
-- topological sort.  The result is an array of labels, from first to
-- last, which is set as the "order" property on the ssa.  Each
-- block will also be given an "order" property.
local function order_blocks(ssa)
   local tail = nil
   local chain = {} -- label -> label | nil
   local visited = {} -- label -> bool
   local function visit(label)
      if not visited[label] then visited[label] = true else return end
      local block = ssa.blocks[label]
      if block.control[1] == 'if' then
         visit(block.control[4])
         visit(block.control[3])
      elseif block.control[1] == 'goto' then
         visit(block.control[2])
      else
         assert(block.control[1] == 'return')
      end
      chain[label] = tail
      tail = label
   end
   visit(ssa.start)
   local order = 1
   ssa.order = {}
   while tail do
      ssa.blocks[tail].order = order
      ssa.order[order] = tail
      tail = chain[tail]
      order = order + 1
   end
end

-- Add a "preds" property to all blocks, which is a list of labels of
-- predecessors.
local function add_predecessors(ssa)
   local function visit(label, block)
      local function add_predecessor(succ)
         table.insert(ssa.blocks[succ].preds, label)
      end
      if block.control[1] == 'if' then
         add_predecessor(block.control[3])
         add_predecessor(block.control[4])
      elseif block.control[1] == 'goto' then
         add_predecessor(block.control[2])
      else
         assert(block.control[1] == 'return')
      end
   end
   for label,block in pairs(ssa.blocks) do block.preds = {} end
   for label,block in pairs(ssa.blocks) do visit(label, block) end
end

-- Add an "idom" property to all blocks, which is the label of the
-- immediate dominator.  It's trivial as we have no loops.
local function compute_idoms(ssa)
   local function dom(d1, d2)
      if d1 == d2 then return d1 end
      -- We exploit the fact that a reverse post-order is a topological
      -- sort, and so the sort order of the idom of a node is always
      -- numerically less than the node itself.
      if ssa.blocks[d1].order < ssa.blocks[d2].order then
         return dom(d1, ssa.blocks[d2].idom)
      else
         return dom(ssa.blocks[d1].idom, d2)
      end
   end
   for order,label in ipairs(ssa.order) do
      local preds = ssa.blocks[label].preds
      if #preds == 0 then
         assert(label == ssa.start)
         -- No idom for the first block.
      else
         local idom = preds[1]
         -- If there is just one predecessor, the idom is that
         -- predecessor.  Otherwise it's the common dominator of the
         -- first predecessor and the other predecessors.
         for j=2,#preds do
            idom = dom(idom, preds[j])
         end
         ssa.blocks[label].idom = idom
      end
   end
end

local function compute_doms(ssa)
   for order,label in ipairs(ssa.order) do
      local block = ssa.blocks[label]
      block.doms = {}
      if block.idom then
         table.insert(ssa.blocks[block.idom].doms, label)
      end
   end
end

function convert_ssa(anf)
   local ssa = optimize_ssa(lower(anf))
   order_blocks(ssa)
   add_predecessors(ssa)
   compute_idoms(ssa)
   compute_doms(ssa)
   if verbose then print_ssa(ssa) end
   return ssa
end

function selftest()
   print("selftest: pf.ssa")
   local parse = require('pf.parse').parse
   local expand = require('pf.expand').expand
   local optimize = require('pf.optimize').optimize
   local convert_anf = require('pf.anf').convert_anf

   local function test(expr)
      return convert_ssa(convert_anf(optimize(expand(parse(expr), "EN10MB"))))
   end

   test("tcp port 80 or udp port 34")

   print("OK")
end
