module(...,package.seeall)

local ffi = require("ffi")
local bit = require("bit")
local band = bit.band

local verbose = os.getenv("PF_VERBOSE");

local function BPF_CLASS(code) return band(code, 0x07) end
local BPF_LD   = 0x00
local BPF_LDX  = 0x01
local BPF_ST   = 0x02
local BPF_STX  = 0x03
local BPF_ALU  = 0x04
local BPF_JMP  = 0x05
local BPF_RET  = 0x06
local BPF_MISC = 0x07

local function BPF_SIZE(code) return band(code, 0x18) end
local BPF_W = 0x00
local BPF_H = 0x08
local BPF_B = 0x10

local function BPF_MODE(code) return band(code, 0xe0) end
local BPF_IMM = 0x00
local BPF_ABS = 0x20
local BPF_IND = 0x40
local BPF_MEM = 0x60
local BPF_LEN = 0x80
local BPF_MSH = 0xa0

local function BPF_OP(code) return band(code, 0xf0) end
local BPF_ADD = 0x00
local BPF_SUB = 0x10
local BPF_MUL = 0x20
local BPF_DIV = 0x30
local BPF_OR = 0x40
local BPF_AND = 0x50
local BPF_LSH = 0x60
local BPF_RSH = 0x70
local BPF_NEG = 0x80
local BPF_JA = 0x00
local BPF_JEQ = 0x10
local BPF_JGT = 0x20
local BPF_JGE = 0x30
local BPF_JSET = 0x40

local function BPF_SRC(code) return band(code, 0x08) end
local BPF_K = 0x00
local BPF_X = 0x08

local function BPF_RVAL(code) return band(code, 0x18) end
local BPF_A = 0x10

local function BPF_MISCOP(code) return band(code, 0xf8) end
local BPF_TAX = 0x00
local BPF_TXA = 0x80

local BPF_MEMWORDS = 16

local MAX_UINT32 = 0xffffffff
local MAX_UINT32_PLUS_1 = MAX_UINT32 + 1

local function runtime_u32(s32)
   if (s32 < 0) then return s32 + MAX_UINT32_PLUS_1 end
   return s32
end

local function runtime_add(a, b)
   return bit.tobit((runtime_u32(a) + runtime_u32(b)) % MAX_UINT32_PLUS_1)
end

local function runtime_sub(a, b)
   return bit.tobit((runtime_u32(a) - runtime_u32(b)) % MAX_UINT32_PLUS_1)
end

local function runtime_mul(a, b)
   -- FIXME: This can overflow.  We need a math.imul.
   return bit.tobit(runtime_u32(a) * runtime_u32(b))
end

local function runtime_div(a, b)
   -- The code generator already asserted b is a non-zero constant.
   return bit.tobit(math.floor(runtime_u32(a) / runtime_u32(b)))
end

local env = {
   bit = require('bit'),
   runtime_u32 = runtime_u32,
   runtime_add = runtime_add,
   runtime_sub = runtime_sub,
   runtime_mul = runtime_mul,
   runtime_div = runtime_div,
}

local function is_power_of_2(k)
   if k == 0 then return false end
   if bit.band(k, runtime_u32(k) - 1) ~= 0 then return false end
   for shift = 0, 31 do
      if bit.lshift(1, shift) == k then return shift end
   end
end

function compile_lua(bpf)
   local head = '';
   local body = '';
   local function write_head(code) head = head .. '   ' .. code .. '\n' end
   local function write_body(code) body = body .. '   ' .. code .. '\n' end
   local write = write_body

   local jump_targets = {}

   local function bin(op, a, b) return '(' .. a .. op .. b .. ')' end
   local function call(proc, args) return proc .. '(' .. args .. ')' end
   local function comma(a1, a2) return a1 .. ', ' .. a2 end
   local function s32(a) return call('bit.tobit', a) end
   local function u32(a)
      if (tonumber(a)) then return runtime_u32(a) end
      return call('runtime_u32', a)
   end
   local function add(a, b)
      if type(b) == 'number' then
         if b == 0 then return a end
         if b > 0 then return s32(bin('+', a, b)) end
      end
      return call('runtime_add', comma(a, b))
   end
   local function sub(a, b) return call('runtime_sub', comma(a, b)) end
   local function mul(a, b) return call('runtime_mul', comma(a, b)) end
   local function div(a, b) return call('runtime_div', comma(a, b)) end
   local function bit(op, a, b) return call('bit.' .. op, comma(a, b)) end
   local function bor(a, b) return bit('bor', a, b) end
   local function band(a, b) return bit('band', a, b) end
   local function lsh(a, b) return bit('lshift', a, b) end
   local function rsh(a, b) return bit('rshift', a, b) end
   local function rol(a, b) return bit('rol', a, b) end
   local function neg(a) return s32('-' .. a) end -- FIXME: Is this right?
   local function ee(a, b) return bin('==', a, b) end
   local function ge(a, b) return bin('>=', a, b) end
   local function gt(a, b) return bin('>', a, b) end
   local function assign(lhs, rhs) return lhs .. ' = ' .. rhs end
   local function label(i) return '::L' .. i .. '::' end
   local function jump(i) jump_targets[i] = true; return 'goto L' .. i end
   local function cond(test, kt, kf, fallthrough)
      if fallthrough == kf then
         return 'if ' .. test .. ' then ' .. jump(kt) .. ' end'
      elseif fallthrough == kt then
         return cond('not '..test, kf, kt, fallthrough)
      else
         return cond(test, kt, kf, kf) .. '\n   ' .. jump(kf)
      end
   end

   local state = {}
   local function declare(name, init)
      if not state[name] then
         write_head(assign('local ' .. name, init or '0'))
         state[name] = true
      end
      return name
   end

   local function A() return declare('A') end        -- accumulator
   local function X() return declare('X') end        -- index
   local function M(k)                               -- scratch
      if (k >= BPF_MEMWORDS or k < 0) then error("bad k" .. k) end
      return declare('M'..k)
   end

   local function size_to_accessor(size)
      if size == BPF_W then return 's32'
      elseif size == BPF_H then return 'u16'
      elseif size == BPF_B then return 'u8'
      else error('bad size ' .. size)
      end
   end

   local function read_buffer_word_by_type(accessor, buffer, offset)
      if (accessor == 'u8') then
         return buffer..'['..offset..']'
      elseif (accessor == 'u16') then
         return 'bit.bor(bit.lshift('..buffer..'['..offset..'], 8), '..
            buffer..'['..offset..'+1])'
      elseif (accessor == 's32') then
         return 'bit.bor(bit.lshift('..buffer..'['..offset..'], 24),'..
            'bit.lshift('..buffer..'['..offset..'+1], 16), bit.lshift('..
            buffer..'['..offset..'+2], 8), '..buffer..'['..offset..'+3])'
      end
   end

   local function P_ref(size, k)
      return read_buffer_word_by_type(size_to_accessor(size), 'P', k)
   end

   local function ld(size, mode, k)
      local rhs, bytes = 0
      if size == BPF_W then bytes = 4
      elseif size == BPF_H then bytes = 2
      elseif size == BPF_B then bytes = 1
      else error('bad size ' .. size)
      end
      if     mode == BPF_ABS then
         assert(k >= 0, "packet size >= 2G???")
         write('if ' .. k + bytes .. ' > length then return false end')
         rhs = P_ref(size, k)
      elseif mode == BPF_IND then
         write(assign(declare('T'), add(X(), k)))
         -- Assuming packet can't be 2GB in length
         write('if T < 0 or T + ' .. bytes .. ' > length then return false end')
         rhs = P_ref(size, 'T')
      elseif mode == BPF_LEN then rhs = 'bit.tobit(length)'
      elseif mode == BPF_IMM then rhs = k
      elseif mode == BPF_MEM then rhs = M(k)
      else                        error('bad mode ' .. mode)
      end
      write(assign(A(), rhs))
   end

   local function ldx(size, mode, k)
      local rhs
      if     mode == BPF_LEN then rhs = 'bit.tobit(length)'
      elseif mode == BPF_IMM then rhs = k
      elseif mode == BPF_MEM then rhs = M(k)
      elseif mode == BPF_MSH then
         assert(k >= 0, "packet size >= 2G???")
         write('if ' .. k .. ' >= length then return false end')
         rhs = lsh(band(P_ref(BPF_B, k), 0xf), 2)
      else
         error('bad mode ' .. mode)
      end
      write(assign(X(), rhs))
   end

   local function st(k)
      write(assign(M(k), A()))
   end

   local function stx(k)
      write(assign(M(k), X()))
   end

   local function alu(op, src, k)
      local b
      if     src == BPF_K then b = k
      elseif src == BPF_X then b = X()
      else error('bad src ' .. src)
      end

      local rhs
      if     op == BPF_ADD then rhs = add(A(), b)
      elseif op == BPF_SUB then rhs = sub(A(), b)
      elseif op == BPF_MUL then
         local bits = is_power_of_2(b)
         if bits then rhs = rol(A(), bits) else rhs = mul(A(), b) end
      elseif op == BPF_DIV then
         assert(src == BPF_K, "division by non-constant value is unsupported")
         assert(k ~= 0, "program contains division by constant zero")
         local bits = is_power_of_2(k)
         if bits then rhs = rsh(A(), bits) else rhs = div(A(), k) end
      elseif op == BPF_OR  then rhs = bor(A(), b)
      elseif op == BPF_AND then rhs = band(A(), b)
      elseif op == BPF_LSH then rhs = lsh(A(), b)
      elseif op == BPF_RSH then rhs = rsh(A(), b)
      elseif op == BPF_NEG then rhs = neg(A())
      else error('bad op ' .. op)
      end
      write(assign(A(), rhs))
   end

   local function jmp(i, op, src, k, jt, jf)
      if op == BPF_JA then
         write(jump(i + runtime_u32(k)))
         return
      end

      local rhs
      if src == BPF_K then rhs = k
      elseif src == BPF_X then rhs = X()
      else error('bad src ' .. src)
      end

      jt = jt + i
      jf = jf + i

      if op == BPF_JEQ then
         write(cond(ee(A(), rhs), jt, jf, i))  -- No need for u32().
      elseif op == BPF_JGT then
         write(cond(gt(u32(A()), u32(rhs)), jt, jf, i))
      elseif op == BPF_JGE then
         write(cond(ge(u32(A()), u32(rhs)), jt, jf, i))
      elseif op == BPF_JSET then
         write(cond(ee(band(A(), rhs), 0), jf, jt, i))
      else
         error('bad op ' .. op)
      end
   end

   local function ret(src, k)
      local rhs
      if src == BPF_K then rhs = k
      elseif src == BPF_A then rhs = A()
      else error('bad src ' .. src)
      end
      local result = u32(rhs) ~= 0 and "true" or "false"
      write('do return '..result..' end')
   end

   local function misc(op)
      if op == BPF_TAX then
         write(assign(X(), A()))
      elseif op == BPF_TXA then
         write(assign(A(), X()))
      else error('bad op ' .. op)
      end
   end

   if verbose then print(disassemble(bpf)) end
   for i=0, #bpf-1 do
      -- for debugging: write('print('..i..')')
      local inst = bpf[i]
      local code = inst.code
      local class = BPF_CLASS(code)
      if     class == BPF_LD  then ld(BPF_SIZE(code), BPF_MODE(code), inst.k)
      elseif class == BPF_LDX then ldx(BPF_SIZE(code), BPF_MODE(code), inst.k)
      elseif class == BPF_ST  then st(inst.k)
      elseif class == BPF_STX then stx(inst.k)
      elseif class == BPF_ALU then alu(BPF_OP(code), BPF_SRC(code), inst.k)
      elseif class == BPF_JMP then jmp(i, BPF_OP(code), BPF_SRC(code), inst.k,
                                       inst.jt, inst.jf)
      elseif class == BPF_RET then ret(BPF_SRC(code), inst.k)
      elseif class == BPF_MISC then misc(BPF_MISCOP(code))
      else error('bad class ' .. class)
      end
      if jump_targets[i] then write(label(i)) end
   end
   local ret = ('return function (P, length)\n' ..
                   head .. body ..
                '   error("end of bpf")\n' ..
                'end')
   if verbose then print(ret) end
   return ret
end

function disassemble(bpf)
   local asm = '';
   local function write(code, ...) asm = asm .. code:format(...) end
   local function writeln(code, ...) write(code..'\n', ...) end

   local function ld(size, mode, k)
      local bytes = assert(({ [BPF_W]=4, [BPF_H]=2, [BPF_B]=1 })[size])
      if     mode == BPF_ABS then writeln('A = P[%u:%u]', k, bytes)
      elseif mode == BPF_IND then writeln('A = P[X+%u:%u]', k, bytes)
      elseif mode == BPF_IMM then writeln('A = %u', k)
      elseif mode == BPF_LEN then writeln('A = length')
      elseif mode == BPF_MEM then writeln('A = M[%u]', k)
      else                        error('bad mode ' .. mode) end
   end

   local function ldx(size, mode, k)
      if     mode == BPF_IMM then writeln('X = %u', k)
      elseif mode == BPF_LEN then writeln('X = length')
      elseif mode == BPF_MEM then writeln('X = M[%u]', k)
      elseif mode == BPF_MSH then writeln('X = (P[%u:1] & 0xF) << 2', k)
      else                        error('bad mode ' .. mode) end
   end

   local function st(k) writeln('M(%u) = A', k) end

   local function stx(k) writeln('M(%u) = X', k) end

   local function alu(op, src, k)
      local b
      if     src == BPF_K then b = k
      elseif src == BPF_X then b = 'X'
      else error('bad src ' .. src) end

      if     op == BPF_ADD then writeln('A += %s', b)
      elseif op == BPF_SUB then writeln('A -= %s', b)
      elseif op == BPF_MUL then writeln('A *= %s', b)
      elseif op == BPF_DIV then writeln('A /= %s', b)
      elseif op == BPF_OR  then writeln('A |= %s', b)
      elseif op == BPF_AND then writeln('A &= %s', b)
      elseif op == BPF_LSH then writeln('A <<= %s', b)
      elseif op == BPF_RSH then writeln('A >>= %s', b)
      elseif op == BPF_NEG then writeln('A = -A')
      else error('bad op ' .. op) end
   end

   local function jmp(i, op, src, k, jt, jf)
      if op == BPF_JA then writeln('goto %u', k); return end

      local rhs
      if src == BPF_K then rhs = k
      elseif src == BPF_X then rhs = 'X'
      else error('bad src ' .. src) end

      jt = jt + i + 1
      jf = jf + i + 1

      local function cond(op, lhs, rhs)
         writeln('if (%s %s %s) goto %u else goto %u', lhs, op, rhs, jt, jf)
      end

      if     op == BPF_JEQ then cond('==', 'A', rhs)
      elseif op == BPF_JGT then cond('>', 'A', rhs)
      elseif op == BPF_JGE then cond('>=', 'A', rhs)
      elseif op == BPF_JSET then cond('!=', 'A & '..rhs, 0)
      else error('bad op ' .. op) end
   end

   local function ret(src, k)
      if     src == BPF_K then writeln('return %u', k)
      elseif src == BPF_A then writeln('return A')
      else error('bad src ' .. src) end
   end

   local function misc(op)
      if op == BPF_TAX then writeln('X = A')
      elseif op == BPF_TXA then writeln('A = X')
      else error('bad op ' .. op) end
   end

   for i=0, #bpf-1 do
      local inst = bpf[i]
      local code = inst.code
      local class = BPF_CLASS(code)
      local k = runtime_u32(inst.k)
      write(string.format('%03d: ', i))
      if     class == BPF_LD  then ld(BPF_SIZE(code), BPF_MODE(code), k)
      elseif class == BPF_LDX then ldx(BPF_SIZE(code), BPF_MODE(code), k)
      elseif class == BPF_ST  then st(k)
      elseif class == BPF_STX then stx(k)
      elseif class == BPF_ALU then alu(BPF_OP(code), BPF_SRC(code), k)
      elseif class == BPF_JMP then jmp(i, BPF_OP(code), BPF_SRC(code), k,
                                       inst.jt, inst.jf)
      elseif class == BPF_RET then ret(BPF_SRC(code), k)
      elseif class == BPF_MISC then misc(BPF_MISCOP(code))
      else error('bad class ' .. class) end
   end
   return asm
end

function compile(bpf)
   local func = assert(loadstring(compile_lua(bpf)))
   setfenv(func, env)
   return func()
end

function dump(bpf)
   io.write(#bpf .. ':\n')
   for i = 0, #bpf-1 do
      io.write(string.format('  {0x%x, %u, %u, %d}\n',
                             bpf[i].code, bpf[i].jt, bpf[i].jf, bpf[i].k))
   end
   io.write("\n")
end

function selftest()
   print("selftest: pf.bpf")
   -- FIXME: Not sure how to test without pcap compilation.
   print("OK")
end
