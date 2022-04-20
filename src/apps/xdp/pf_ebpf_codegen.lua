-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- This module implements code generation for the XDP/eBPF backend of
-- Pflua. It takes the result of instruction selection (selection.lua)
-- and register allocation (regalloc.lua) and generates a function with
-- eBPF bytecode.

local parse = require('pf.parse').parse
local expand = require('pf.expand').expand
local optimize = require('pf.optimize').optimize
local anf = require('pf.anf')
local ssa = require('pf.ssa')
local sel = require("pf.selection")
local ra = require("pf.regalloc")
local bpf = require("apps.xdp.bpf")

local c, f, m, a, s, j = bpf.c, bpf.f, bpf.m, bpf.a, bpf.s, bpf.j

local tobit, band, bor, rshift = bit.tobit, bit.band, bit.bor, bit.rshift

-- eBPF register allocation:
--   * mark r1 callee save: holds the xdp_md context we wish to preserve
--   * omit r0: we will keep a pointer to the packet payload in here
--   * omit r2: we will use this register to perform length checks
--   * use r3 as len: we will store data_end here (used in length checks)
local ebpf_regs = {
   caller_regs = { 9, 8, 7, 6, 5, 4, 3 },
   callee_regs = { 1 },
   len = 3
}

-- Generate a eBPF XDP program that will return XDP_PASS unless filter expr
-- matches, and otherwise "fall-though" as to allow execution of a further eBPF
-- program that is to be appended.
function codegen (ir, alloc)
   -- push callee-save registers if we use any
   local to_pop = {}
   for reg, _ in pairs(alloc.callee_saves) do
      error("NYI: callee saves")
      -- we need to record the order in which to pop
      -- b/c while the push order doesn't matter, the
      -- pop order must be reverse (and callee_saves
      -- is an unordered set)
      table.insert(to_pop, reg)
   end

   -- in bytes
   local stack_slot_size = 8

   -- allocate space for all spilled vars
   local spilled_space = 0
   for _, _ in pairs(alloc.spills) do
      spilled_space = spilled_space + stack_slot_size
   end
   if spilled_space > 0 then
      error("NYI: spilled space")
   end

   -- if the length variable got spilled, we need to explicitly initialize
   -- the stack slot for it
   if alloc.spills["len"] then
      error("NYI: spilled length")
   end

   local pc, tr = 1, {}
   local function emit (ins)
      tr[pc] = ins
      pc = pc+1
   end

   local label_offset, labels = 2, {}

   local cmp
   local function emit_cjmp (cond, target)
      assert(cmp, "cjmp needs preceeding cmp")
      local jmp = cmp; cmp = nil
      jmp.op = bor(c.JMP, cond, jmp.op)
      if target == "true-label" then
         jmp.off = 0
      elseif target == "false-label" then
         jmp.off = 1
      else
         jmp.off = label_offset+target
      end
      emit(jmp)
   end

   -- Setup: move data start and end pointers into r0 and r(alloc.len)
   -- r0 = ((struct xdp_md *)ctx)->data
   emit{ op=bor(c.LDX, f.W, m.MEM), dst=0, src=1, off=0 }
   -- r(alloc.len) = ((struct xdp_md *)ctx)->data_end
   emit{ op=bor(c.LDX, f.W, m.MEM), dst=alloc.len, src=1, off=4 }

   for idx, instr in ipairs(ir) do
      local itype = instr[1]

      --- FIXME: handle spills

      -- the core code generation logic starts here
      if itype == "label" then
         local lnum = instr[2]
         labels[label_offset+lnum] = pc

      elseif itype == "cjmp" then
         local op, target = instr[2], instr[3]

            if op == "=" then
               emit_cjmp(j.JEQ, target)
            elseif op == "!=" then
               emit_cjmp(j.JNE, target)
            elseif op == ">=" then
               emit_cjmp(j.JGE, target)
            elseif op == "<=" then
               emit_cjmp(j.JLE, target)
            elseif op == ">" then
               emit_cjmp(j.JGT, target)
            elseif op == "<" then
               emit_cjmp(j.JLT, target)
            end

      elseif itype == "jmp" then
         local next_instr = ir[idx+1]
         -- if the jump target is immediately after this in the instruction
         -- sequence then don't generate the jump
         if (type(instr[2]) == "number" and
             next_instr[1] == "label" and
             next_instr[2] == instr[2]) then
            -- don't output anything
         else
            if instr[2] == "true-label" then
               if next_instr[1] ~= "ret-true" then
                  emit{ op=bor(c.JMP, j.JA), off=0 }
               end
            elseif instr[2] == "false-label" then
               if next_instr[1] ~= "ret-false" then
                  emit{ op=bor(c.JMP, j.JA), off=1 }
               end
            else
               emit{ op=bor(c.JMP, j.JA), off=label_offset+instr[2] }
            end
         end

      elseif itype == "cmp" and instr[2] == "len" then
         local lhs_reg = alloc.len
         local rhs = instr[3]
         assert(rhs ~= "len", "NYI: cmp with rhs len")

         -- Perform eBPF friendly length check.
         -- mov r2, r0
         emit{ op=bor(c.ALU64, a.MOV, s.X), dst=2, src=0 }
         -- add r2, rhs
         if type(rhs) == "number" then
            emit{ op=bor(c.ALU64, a.ADD, s.K), dst=2, imm=rhs }
         else
            emit{ op=bor(c.ALU64, a.ADD, s.X), dst=2, src=alloc[rhs] }
         end
         -- cmp r6, r2
         cmp = { op=s.X, dst=lhs_reg, src=2 }

      elseif itype == "cmp" then
         -- the lhs should never be an immediate so this should be non-nil
         local lhs_reg = assert(alloc[instr[2]])
         local rhs = instr[3]
         assert(rhs ~= "len", "NYI: cmp with rhs len")

         if type(rhs) == "number" then
            cmp = { op=s.K, dst=lhs_reg, imm=rhs }
         else
            local rhs_reg = alloc[rhs]
            cmp = { op=s.X, dst=lhs_reg, src=rhs_reg }
         end

      elseif itype == "load" then
         local target = alloc[instr[2]]
         assert(not alloc.spills[instr[2]], "NYI: load spill")
         local offset = instr[3]
         local bytes  = instr[4]

         if type(offset) == "number" then
            if bytes == 1 then
               emit{ op=bor(c.LDX, f.B, m.MEM), dst=target, off=offset }
            elseif bytes == 2 then
               emit{ op=bor(c.LDX, f.H, m.MEM), dst=target, off=offset }
            else
               emit{ op=bor(c.LDX, f.W, m.MEM), dst=target, off=offset }
            end
         else
            local reg = alloc[offset]
            assert(not alloc.spills[offset], "NYI: load spill")

            emit{ op=bor(c.ALU64, a.ADD, s.X), dst=reg }
            if bytes == 1 then
               emit{ op=bor(c.LDX, f.B, m.MEM), dst=target, src=reg }
            elseif bytes == 2 then
               emit{ op=bor(c.LDX, f.H, m.MEM), dst=target, src=reg }
            else
               emit{ op=bor(c.LDX, f.W, m.MEM), dst=target, src=reg }
            end
            emit{ op=bor(c.ALU64, a.SUB, s.X), dst=reg }
         end

      elseif itype == "mov" then
         local dst   = alloc[instr[2]]
         assert(not alloc.spills[instr[2]], "NYI: mov spill")
         local arg   = instr[3]

         if type(arg) == "number" then
            emit{ op=bor(c.ALU, a.MOV, s.K), dst=dst, imm=arg }
         else
            assert(not alloc.spills[arg], "NYI: mov spill")
            emit{ op=bor(c.ALU64, a.MOV, s.X), dst=dst, src=alloc[arg] }
         end

      elseif itype == "mov64" then
         local dst = alloc[instr[2]]
         local imm = instr[3]
      emit{ op=bor(c.LD, f.DW, m.IMM), dst=dst, src=s.K, imm=tobit(imm)  }
      emit{                                              imm=rshift(imm, 32) }

      elseif itype == "add" then
         local reg1, reg2 = alloc[instr[2]], alloc[instr[3]]
         emit{ op=bor(c.ALU64, a.ADD, s.X), dst=reg1, src=reg2 }

      elseif itype == "sub" then
         local reg1, reg2 = alloc[instr[2]], alloc[instr[3]]
         emit{ op=bor(c.ALU64, a.SUB, s.X), dst=reg1, src=reg2 }

      elseif itype == "mul" then
         local reg1, reg2 = alloc[instr[2]], alloc[instr[3]]
         emit{ op=bor(c.ALU64, a.MUL, s.X), dst=reg1, src=reg2 }

      -- For division we use floating point division to avoid having
      -- to deal with the %eax register for the div instruction.
      elseif itype == "div" then
         local reg1, reg2 = alloc[instr[2]], alloc[instr[3]]
         emit{ op=bor(c.ALU64, a.DIV, s.X), dst=reg1, src=reg2 }

      elseif itype == "and" then
         local reg1, reg2 = alloc[instr[2]], alloc[instr[3]]
         emit{ op=bor(c.ALU64, a.AND, s.X), dst=reg1, src=reg2 }

      elseif itype == "or" then
         local reg1, reg2 = alloc[instr[2]], alloc[instr[3]]
         emit{ op=bor(c.ALU64, a.OR, s.X), dst=reg1, src=reg2 }

      elseif itype == "xor" then
         local reg1, reg2 = alloc[instr[2]], alloc[instr[3]]
         emit{ op=bor(c.ALU64, a.XOR, s.X), dst=reg1, src=reg2 }

      elseif itype == "shl" then
         local reg1, reg2 = alloc[instr[2]], alloc[instr[3]]
         emit{ op=bor(c.ALU64, a.LSH, s.X), dst=reg1, src=reg2 }

      elseif itype == "shr" then
         local reg1, reg2 = alloc[instr[2]], alloc[instr[3]]
         emit{ op=bor(c.ALU64, a.RSH, s.X), dst=reg1, src=reg2 }

      elseif itype == "add-i" then
         local reg = alloc[instr[2]]
         emit{ op=bor(c.ALU64, a.ADD, s.K), dst=reg, imm=instr[3] }

      elseif itype == "sub-i" then
         local reg = alloc[instr[2]]
         emit{ op=bor(c.ALU64, a.SUB, s.K), dst=reg, imm=instr[3] }

      elseif itype == "mul-i" then
         local r = alloc[instr[2]]
         emit{ op=bor(c.ALU64, a.MUL, s.K), dst=reg, imm=instr[3] }

      elseif itype == "and-i" then
         local reg = alloc[instr[2]]
         assert(type(reg) == "number")
         assert(type(instr[3]) == "number")
         emit{ op=bor(c.ALU64, a.AND, s.K), dst=reg, imm=instr[3] }

      elseif itype == "or-i" then
         local reg = alloc[instr[2]]
         assert(type(reg) == "number")
         assert(type(instr[3]) == "number")
         emit{ op=bor(c.ALU64, a.OR, s.K), dst=reg, imm=instr[3] }

      elseif itype == "xor-i" then
         local reg = alloc[instr[2]]
         assert(type(reg) == "number")
         assert(type(instr[3]) == "number")
         emit{ op=bor(c.ALU64, a.XOR, s.K), dst=reg, imm=instr[3] }

      elseif itype == "shl-i" then
         local reg = alloc[instr[2]]
         emit{ op=bor(c.ALU64, a.LSH, s.K), dst=reg, imm=instr[3] }

      elseif itype == "shr-i" then
         local reg = alloc[instr[2]]
         emit{ op=bor(c.ALU64, a.RSH, s.K), dst=reg, imm=instr[3] }

      elseif itype == "ntohs" then
         local reg = alloc[instr[2]]
         emit{ op=bor(c.ALU, a.END, a.BE), dst=reg, imm=16 }

      elseif itype == "ntohl" then
         local reg = alloc[instr[2]]
         emit{ op=bor(c.ALU, a.END, a.BE), dst=reg, imm=32 }

      elseif itype == "uint32" then
         local reg = alloc[instr[2]]
         emit{ op=bor(c.ALU, a.AND, s.X), dst=reg, src=reg }

      elseif itype == "ret-true" then
         labels[0] = pc
         -- In the end, we will turn this into a jump to the first instruction
         -- beyond the end of the emitted sequence.
         emit{ op=bor(c.JMP, j.JA) }

      elseif itype == "ret-false" then
         labels[1] = pc
         -- r0 = XDP_PASS
         emit{ op=bor(c.ALU, a.MOV, s.K), dst=0, imm=2 }
         -- EXIT:
         emit{ op=bor(c.JMP, j.EXIT) }

      elseif itype == "nop" then
         -- don't output anything

      else
	 error(string.format("NYI instruction %s", itype))
      end
   end

   -- Fixup true-label
   local true_label = labels[0]
   if true_label == #tr then
      -- True-label is last instruction: remove its target instruction
      tr[true_label] = nil
   elseif true_label then
      -- Set the jump offset to the first ins. beyond the emitted sequence
      tr[true_label].off = #tr - true_label
   end

   -- Fixup jump offsets
   for pc, ins in ipairs(tr) do
      if band(ins.op, c.JMP) == c.JMP and ins.off then
         ins.off = labels[ins.off] - (pc+1)
      end
   end

   return tr
end

function compile(filter, dump)
   local expr = optimize(expand(parse(filter), "EN10MB"))
   local ssa = ssa.convert_ssa(anf.convert_anf(expr))
   local ir = sel.select(ssa)
   local alloc = ra.allocate(ir, ebpf_regs)
   local code = codegen(ir, alloc)
   if dump then
      require("core.lib").print_object(alloc)
      require("core.lib").print_object(ir)
      print(filter)
      bpf.dis(bpf.asm(code))
   end
   return code
end

function selftest()
   compile("ip proto esp or ip proto 99 or arp", "dump")
   compile("ip6[6] = 50 or ip6[6] = 99 or "..
              "(ip6[6] = 58 and (ip6[40] = 135 or ip6[40] = 136))",
           "dump")
   compile("1 = 2",
           "dump")
end
