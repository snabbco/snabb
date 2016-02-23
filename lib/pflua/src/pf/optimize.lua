module(...,package.seeall)

local bit = require('bit')
local utils = require('pf.utils')

local verbose = os.getenv("PF_VERBOSE");

local expand_arith, expand_relop, expand_bool

local set, concat, dup, pp = utils.set, utils.concat, utils.dup, utils.pp

-- Pflang's numbers are unsigned 32-bit integers, but sometimes we use
-- negative numbers because the bitops module prefers them.
local UINT32_MAX = 2^32-1
local INT32_MAX = 2^31-1
local INT32_MIN = -2^31
local UINT16_MAX = 2^16-1

-- We use use Lua arithmetic to implement pflang operations, so
-- intermediate results can exceed the int32|uint32 range.  Those
-- intermediate results are then clamped back to the range with the
-- 'int32' or 'uint32' operations.  Multiplication is clamped internally
-- by the '*64' operation.  We'll never see a value outside this range.
local INT_MAX = UINT32_MAX + UINT32_MAX
local INT_MIN = INT32_MIN + INT32_MIN

local relops = set('<', '<=', '=', '!=', '>=', '>')

local binops = set(
   '+', '-', '*', '*64', '/', '&', '|', '^', '<<', '>>'
)
local associative_binops = set(
   '+', '*', '*64', '&', '|', '^'
)
local bitops = set('&', '|', '^')
local unops = set('ntohs', 'ntohl', 'uint32', 'int32')
-- ops that produce results of known types
local int32ops = set('&', '|', '^', 'ntohs', 'ntohl', '<<', '>>', 'int32')
local uint32ops = set('uint32', '[]')
-- ops that coerce their arguments to be within range
local coerce_ops = set('&', '|', '^', 'ntohs', 'ntohl', '<<', '>>', 'int32',
                       'uint32')

local folders = {
   ['+'] = function(a, b) return a + b end,
   ['-'] = function(a, b) return a - b end,
   ['*'] = function(a, b) return a * b end,
   ['*64'] = function(a, b) return tonumber((a * 1LL * b) % 2^32) end,
   ['/'] = function(a, b)
      -- If the denominator is zero, the code is unreachable, so it
      -- doesn't matter what we return.
      if b == 0 then return 0 end
      return math.floor(a / b)
   end,
   ['&'] = function(a, b) return bit.band(a, b) end,
   ['^'] = function(a, b) return bit.bxor(a, b) end,
   ['|'] = function(a, b) return bit.bor(a, b) end,
   ['<<'] = function(a, b) return bit.lshift(a, b) end,
   ['>>'] = function(a, b) return bit.rshift(a, b) end,
   ['ntohs'] = function(a) return bit.rshift(bit.bswap(a), 16) end,
   ['ntohl'] = function(a) return bit.bswap(a) end,
   ['uint32'] = function(a) return a % 2^32 end,
   ['int32'] = function(a) return bit.tobit(a) end,
   ['='] = function(a, b) return a == b end,
   ['!='] = function(a, b) return a ~= b end,
   ['<'] = function(a, b) return a < b end,
   ['<='] = function(a, b) return a <= b end,
   ['>='] = function(a, b) return a >= b end,
   ['>'] = function(a, b) return a > b end
}

local cfkey_cache, cfkey = {}, nil

local function memoize(f)
   return function (arg)
      local result = cfkey_cache[arg]
      if result == nil then
         result = f(arg)
         cfkey_cache[arg] = result
      end
      return result
   end
end

local function clear_cache()
   cfkey_cache = {}
end

cfkey = memoize(function (expr)
   if type(expr) == 'table' then
      local parts = {'('}
      for i=1,#expr do
         parts[i+1] = cfkey(expr[i])
      end
      parts[#parts+1] = ')'
      return table.concat(parts, " ")
   else
      return expr
   end
end)

-- A simple expression can be duplicated.  FIXME: Some calls are simple,
-- some are not.  For now our optimizations don't work very well if we
-- don't allow duplication though.
local simple = set('true', 'false', 'match', 'fail', 'call')
local tailops = set('fail', 'match', 'call')
local trueops = set('match', 'call', 'true')

local commute = {
   ['<']='>', ['<=']='>=', ['=']='=', ['!=']='!=', ['>=']='<=', ['>']='<'
}

local function try_invert(relop, expr, C)
   assert(type(C) == 'number' and type(expr) ~= 'number')
   local op = expr[1]
   local is_eq = relop == '=' or relop == '!='
   if op == 'ntohl' and is_eq then
      local rhs = expr[2]
      if int32ops[rhs[1]] then
         assert(INT32_MIN <= C and C <= INT32_MAX)
         -- ntohl(INT32) = C => INT32 = ntohl(C)
         return relop, rhs, assert(folders[op])(C)
      elseif uint32ops[rhs[1]] then
         -- ntohl(UINT32) = C => UINT32 = uint32(ntohl(C))
         return relop, rhs, assert(folders[op])(C) % 2^32
      end
   elseif op == 'ntohs' and is_eq then
      local rhs = expr[2]
      if ((rhs[1] == 'ntohs' or (rhs[1] == '[]' and rhs[3] <= 2))
           and 0 <= C and C <= UINT16_MAX) then
         -- ntohs(UINT16) = C => UINT16 = ntohs(C)
         return relop, rhs, assert(folders[op])(C)
      end
   elseif op == 'uint32' and is_eq then
      local rhs = expr[2]
      if int32ops[rhs[1]] then
         -- uint32(INT32) = C => INT32 = int32(C)
         return relop, rhs, bit.tobit(C)
      end
   elseif op == 'int32' and is_eq then
      local rhs = expr[2]
      if uint32ops[rhs[1]] then
         -- int32(UINT32) = C => UINT32 = uint32(C)
         return relop, rhs, C ^ 2^32
      end
   elseif bitops[op] and is_eq then
      local lhs, rhs = expr[2], expr[3]
      if type(lhs) == 'number' and rhs[1] == 'ntohl' then
         -- bitop(C, ntohl(X)) = C => bitop(ntohl(C), X) = ntohl(C)
         local swap = assert(folders[rhs[1]])
         return relop, { op, swap(lhs), rhs[2] }, swap(C)
      elseif type(rhs) == 'number' and lhs[1] == 'ntohl' then
         -- bitop(ntohl(X), C) = C => bitop(X, ntohl(C)) = ntohl(C)
         local swap = assert(folders[lhs[1]])
         return relop, { op, lhs[2], swap(rhs) }, swap(C)
      elseif op == '&' then
         if type(lhs) == 'number' then lhs, rhs = rhs, lhs end
         if (type(lhs) == 'table' and lhs[1] == 'ntohs'
             and type(rhs) == 'number' and 0 <= C and C <= UINT16_MAX) then
            -- ntohs(X) & C = C => X & ntohs(C) = ntohs(C)
            local swap = assert(folders[lhs[1]])
            return relop, { op, lhs[2], swap(rhs) }, swap(C)
         end
      end
   end
   return relop, expr, C
end

local simplify_if

local function simplify(expr, is_tail)
   if type(expr) ~= 'table' then return expr end
   local op = expr[1]
   local function decoerce(expr)
      if (type(expr) == 'table'
          and (expr[1] == 'uint32' or expr[1] == 'int32')) then
         return expr[2]
      end
      return expr
   end
   if binops[op] then
      local lhs = simplify(expr[2])
      local rhs = simplify(expr[3])
      if type(lhs) == 'number' and type(rhs) == 'number' then
         return assert(folders[op])(lhs, rhs)
      elseif associative_binops[op] then
         -- Try to make the right operand a number.
         if type(lhs) == 'number' then
            lhs, rhs = rhs, lhs
         end
         if type(lhs) == 'table' and lhs[1] == op and type(lhs[3]) == 'number' then
            if type(rhs) == 'number' then
               -- (A op N1) op N2 -> A op (N1 op N2)
               return { op, lhs[2], assert(folders[op])(lhs[3], rhs) }
            elseif type(rhs) == 'table' and rhs[1] == op and type(rhs[3]) == 'number' then
               -- (A op N1) op (B op N2) -> (A op B) op (N1 op N2)
               return { op, { op, lhs[2], rhs[2] }, assert(folders[op])(lhs[3], rhs[3]) }
            else
               -- (A op N) op X -> (A op X) op N
               return { op, { op, lhs[2], rhs }, lhs[3] }
            end
         elseif type(rhs) == 'table' and rhs[1] == op and type(rhs[3]) == 'number' then
            -- X op (A op N) -> (X op A) op N
            return { op, { op, lhs, rhs[2]}, rhs[3] }
         end
         if coerce_ops[op] then lhs, rhs = decoerce(lhs), decoerce(rhs) end
      end
      return { op, lhs, rhs }
   elseif unops[op] then
      local rhs = simplify(expr[2])
      if type(rhs) == 'number' then return assert(folders[op])(rhs) end
      if op == 'int32' and int32ops[rhs[1]] then return rhs end
      if op == 'uint32' and uint32ops[rhs[1]] then return rhs end
      if coerce_ops[op] then rhs = decoerce(rhs) end
      return { op, rhs }
   elseif relops[op] then
      local lhs = simplify(expr[2])
      local rhs = simplify(expr[3])
      if type(lhs) == 'number' then
         if type(rhs) == 'number' then
            return { assert(folders[op])(lhs, rhs) and 'true' or 'false' }
         end
         op, lhs, rhs = try_invert(assert(commute[op]), rhs, lhs)
      elseif type(rhs) == 'number' then
         op, lhs, rhs = try_invert(op, lhs, rhs)
      end
      return { op, lhs, rhs }
   elseif op == 'if' then
      local test = simplify(expr[2])
      local t, f = simplify(expr[3], is_tail), simplify(expr[4], is_tail)
      return simplify_if(test, t, f)
   elseif op == 'call' then
      local ret = { 'call', expr[2] }
      for i=3,#expr do
         table.insert(ret, simplify(expr[i]))
      end
      return ret
   else
      if op == 'match' or op == 'fail' then return expr end
      if op == 'true' then
         if is_tail then return { 'match' } end
         return expr
      end
      if op == 'false' then
         if is_tail then return { 'fail' } end
         return expr
      end
      assert(op == '[]' and #expr == 3)
      return { op, simplify(expr[2]), expr[3] }
   end
end

function simplify_if(test, t, f)
   local op = test[1]
   if op == 'true' then return t
   elseif op == 'false' then return f
   elseif tailops[op] then return test
   elseif t[1] == 'true' and f[1] == 'false' then return test
   elseif t[1] == 'match' and f[1] == 'fail' then return test
   elseif t[1] == 'fail' and f[1] == 'fail' then return { 'fail' }
   elseif op == 'if' then
      if tailops[test[3][1]] then
         -- if (if A tail B) C D -> if A tail (if B C D)
         return simplify_if(test[2], test[3], simplify_if(test[4], t, f))
      elseif tailops[test[4][1]] then
         -- if (if A B tail) C D -> if A (if B C D) tail
         return simplify_if(test[2], simplify_if(test[3], t, f), test[4])
      elseif test[3][1] == 'false' and test[4][1] == 'true' then
         -- if (if A false true) C D -> if A D C
         return simplify_if(test[2], f, t)
      end
      if t[1] == 'if' and cfkey(test[2]) == cfkey(t[2]) then
         if f[1] == 'if' and cfkey(test[2]) == cfkey(f[2]) then
            -- if (if A B C) (if A D E) (if A F G)
            -- -> if A (if B D F) (if C E G)
            return simplify_if(test[2],
                               simplify_if(test[3], t[3], f[3]),
                               simplify_if(test[4], t[4], f[4]))
         elseif simple[f[1]] then
            -- if (if A B C) (if A D E) F
            -- -> if A (if B D F) (if C E F)
            return simplify_if(test[2],
                               simplify_if(test[3], t[3], f),
                               simplify_if(test[4], t[4], f))
         end
      end
      if f[1] == 'if' then
         if cfkey(test[2]) == cfkey(f[2]) and simple[t[1]] then
            -- if (if A B C) D (if A E F)
            -- -> if A (if B D E) (if C D F)
            return simplify_if(test[2],
                               simplify_if(test[3], t, f[3]),
                               simplify_if(test[4], t, f[4]))
         elseif (test[4][1] == 'false'
                 and f[2][1] == 'if' and f[2][4][1] == 'false'
                 and simple[f[4][1]]
                 and cfkey(test[2]) == cfkey(f[2][2])) then
            -- if (if T A false) B (if (if T C false) D E)
            -- -> if T (if A B (if C D E)) E
            local T, A, B, C, D, E = test[2], test[3], t, f[2][3], f[3], f[4]
            return simplify_if(T, simplify_if(A, B, simplify_if(C, D, E)), E)
         end
      end
   end
   if f[1] == 'if' and cfkey(t) == cfkey(f[3]) and not simple[t[1]] then
      -- if A B (if C B D) -> if (if A true C) B D
      return simplify_if(simplify_if(test, { 'true' }, f[2]), t, f[4])
   end
   if t[1] == 'if' and cfkey(f) == cfkey(t[4]) and not simple[f[1]] then
      -- if A (if B C D) D -> if (if A B false) C D
      return simplify_if(simplify_if(test, t[2], { 'false' }), t[3], f)
   end
   return { 'if', test, t, f }
end

-- Conditional folding.
local function cfold(expr, db)
   if type(expr) ~= 'table' then return expr end
   local op = expr[1]
   if binops[op] then return expr
   elseif unops[op] then return expr
   elseif relops[op] then
      local key = cfkey(expr)
      if db[key] ~= nil then
         return { db[key] and 'true' or 'false' }
      else
         return expr
      end
   elseif op == 'if' then
      local test = cfold(expr[2], db)
      local key = cfkey(test)
      if db[key] ~= nil then
         if db[key] then return cfold(expr[3], db) end
         return cfold(expr[4], db)
      else
         local db_kt = tailops[expr[4][1]] and db or dup(db)
         local db_kf = tailops[expr[3][1]] and db or dup(db)
         db_kt[key] = true
         db_kf[key] = false
         return { op, test, cfold(expr[3], db_kt), cfold(expr[4], db_kf) }
      end
   else
      return expr
   end
end

-- Range inference.
local function Range(min, max)
   assert(min == min, 'min is NaN')
   assert(max == max, 'max is NaN')
   -- if min is less than max, we have unreachable code.  still, let's
   -- not violate assumptions (e.g. about wacky bitshift semantics)
   if min > max then min, max = min, min end
   local ret = { min_ = min, max_ = max }
   function ret:min() return self.min_ end
   function ret:max() return self.max_ end
   function ret:range() return self:min(), self:max() end
   function ret:fold()
      if self:min() == self:max() then
         return self:min()
      end
   end
   function ret:lt(other) return self:max() < other:min() end
   function ret:gt(other) return self:min() > other:max() end
   function ret:union(other)
      return Range(math.min(self:min(), other:min()),
                   math.max(self:max(), other:max()))
   end
   function ret:restrict(other)
      return Range(math.max(self:min(), other:min()),
                   math.min(self:max(), other:max()))
   end
   function ret:tobit()
      if (self:max() - self:min() < 2^32
          and bit.tobit(self:min()) <= bit.tobit(self:max())) then
         return Range(bit.tobit(self:min()), bit.tobit(self:max()))
      end
      return Range(INT32_MIN, INT32_MAX)
   end
   function ret.binary(lhs, rhs, op) -- for monotonic functions
      local fold = assert(folders[op])
      local a = fold(lhs:min(), rhs:min())
      local b = fold(lhs:min(), rhs:max())
      local c = fold(lhs:max(), rhs:max())
      local d = fold(lhs:max(), rhs:min())
      return Range(math.min(a, b, c, d), math.max(a, b, c, d))
   end
   function ret.add(lhs, rhs) return lhs:binary(rhs, '+') end
   function ret.sub(lhs, rhs) return lhs:binary(rhs, '-') end
   function ret.mul(lhs, rhs) return lhs:binary(rhs, '*') end
   function ret.mul64(lhs, rhs) return Range(0, UINT32_MAX) end
   function ret.div(lhs, rhs)
      local rhs_min, rhs_max = rhs:min(), rhs:max()
      -- 0 is prohibited by assertions, so we won't hit it at runtime,
      -- but we could still see { '/', 0, 0 } in the IR when it is
      -- dominated by an assertion that { '!=', 0, 0 }.  The resulting
      -- range won't include the rhs-is-zero case.
      if rhs_min == 0 then
         -- If the RHS is (or folds to) literal 0, we certainly won't
         -- reach here so we can make up whatever value we want.
         if rhs_max == 0 then return Range(0, 0) end
         rhs_min = 1
      elseif rhs_max == 0 then
         rhs_max = -1
      end
      -- Now that we have removed 0 from the limits,
      -- if the RHS can't change sign, we can use binary() on its range.
      if rhs_min > 0 or rhs_max < 0 then
         return lhs:binary(Range(rhs_min, rhs_max), '/')
      end
      -- Otherwise we can use binary() on the two semi-ranges.
      local low, high = Range(rhs_min, -1), Range(1, rhs_max)
      return lhs:binary(low, '/'):union(lhs:binary(high, '/'))
   end
   function ret.band(lhs, rhs)
      lhs, rhs = lhs:tobit(), rhs:tobit()
      if lhs:min() < 0 and rhs:min() < 0 then
         return Range(INT32_MIN, INT32_MAX)
      end
      return Range(0, math.max(math.min(lhs:max(), rhs:max()), 0))
   end
   function ret.bor(lhs, rhs)
      lhs, rhs = lhs:tobit(), rhs:tobit()
      local function saturate(x)
         local y = 1
         while y < x do y = y * 2 end
         return y - 1
      end
      if lhs:min() < 0 or rhs:min() < 0 then return Range(INT32_MIN, -1) end
      return Range(bit.bor(lhs:min(), rhs:min()),
                   saturate(bit.bor(lhs:max(), rhs:max())))
   end
   function ret.bxor(lhs, rhs) return lhs:bor(rhs) end
   function ret.lshift(lhs, rhs)
      lhs, rhs = lhs:tobit(), rhs:tobit()
      local function npot(x) -- next power of two
         if x >= 2^31 then return 32 end
         local n, i = 1, 1
         while n < x do n, i = n * 2, i + 1 end
         return i
      end
      if lhs:min() >= 0 then
         local min_lhs, max_lhs = lhs:min(), lhs:max()
         -- It's nuts, but lshift does an implicit modulo on the RHS.
         local min_shift, max_shift = 0, 31
         if rhs:min() >= 0 and rhs:max() < 32 then
            min_shift, max_shift = rhs:min(), rhs:max()
         end
         if npot(max_lhs) + max_shift < 32 then
            assert(bit.lshift(max_lhs, max_shift) > 0)
            return Range(bit.lshift(min_lhs, min_shift),
                         bit.lshift(max_lhs, max_shift))
         end
      end
      return Range(INT32_MIN, INT32_MAX)
   end
   function ret.rshift(lhs, rhs)
      lhs, rhs = lhs:tobit(), rhs:tobit()
      local min_lhs, max_lhs = lhs:min(), lhs:max()
      -- Same comments wrt modulo of shift.
      local min_shift, max_shift = 0, 31
      if rhs:min() >= 0 and rhs:max() < 32 then
         min_shift, max_shift = rhs:min(), rhs:max()
      end
      if min_shift > 0 then
         -- If we rshift by 1 or more, result will not be negative.
         if min_lhs >= 0 and max_lhs < 2^32 then
            return Range(bit.rshift(min_lhs, max_shift),
                         bit.rshift(max_lhs, min_shift))
         else
            -- -1 is "all bits set".
            return Range(bit.rshift(-1, max_shift),
                         bit.rshift(-1, min_shift))
         end
      elseif min_lhs >= 0 and max_lhs < 2^31 then
         -- Left-hand-side in [0, 2^31): result not negative.
         return Range(bit.rshift(min_lhs, max_shift),
                      bit.rshift(max_lhs, min_shift))
      else
         -- Otherwise punt.
         return Range(INT32_MIN, INT32_MAX)
      end
   end
   return ret
end

local function infer_ranges(expr)
   local function cons(car, cdr) return { car, cdr } end
   local function car(pair) return pair[1] end
   local function cdr(pair) return pair[2] end
   local function cadr(pair) return car(cdr(pair)) end
   local function push(db) return cons({}, db) end
   local function lookup(db, expr)
      if type(expr) == 'number' then return Range(expr, expr) end
      local key = cfkey(expr)
      while db do
         local range = car(db)[key]
         if range then return range end
         db = cdr(db)
      end
      if expr == 'len' then return Range(0, UINT16_MAX) end
      return Range(INT_MIN, INT_MAX)
   end
   local function define(db, expr, range)
      if type(expr) == 'number' then return expr end
      car(db)[cfkey(expr)] = range
      if range:fold() then return range:min() end
      return expr
   end
   local function restrict(db, expr, range)
      return define(db, expr, lookup(db, expr):restrict(range))
   end
   local function merge(db, head)
      for key, range in pairs(head) do car(db)[key] = range end
   end
   local function union(db, h1, h2)
      for key, range1 in pairs(h1) do
         local range2 = h2[key]
         if range2 then car(db)[key] = range1:union(range2) end
      end
   end

   -- Returns lhs true range, lhs false range, rhs true range, rhs false range
   local function branch_ranges(op, lhs, rhs)
      local function lt(a, b)
         return Range(a:min(), math.min(a:max(), b:max() - 1))
      end
      local function le(a, b)
         return Range(a:min(), math.min(a:max(), b:max()))
      end
      local function eq(a, b)
         return Range(math.max(a:min(), b:min()), math.min(a:max(), b:max()))
      end
      local function ge(a, b)
         return Range(math.max(a:min(), b:min()), a:max())
      end
      local function gt(a, b)
         return Range(math.max(a:min(), b:min()+1), a:max())
      end
      if op == '<' then
         return lt(lhs, rhs), ge(lhs, rhs), gt(rhs, lhs), le(rhs, lhs)
      elseif op == '<=' then
         return le(lhs, rhs), gt(lhs, rhs), ge(rhs, lhs), lt(rhs, lhs)
      elseif op == '=' then
         -- Could restrict false continuations more.
         return eq(lhs, rhs), lhs, eq(rhs, lhs), rhs
      elseif op == '!=' then
         return lhs, eq(lhs, rhs), rhs, eq(rhs, lhs)
      elseif op == '>=' then
         return ge(lhs, rhs), lt(lhs, rhs), le(rhs, lhs), gt(rhs, lhs)
      elseif op == '>' then
         return gt(lhs, rhs), le(lhs, rhs), lt(rhs, lhs), ge(rhs, lhs)
      else
         error('unimplemented '..op)
      end
   end
   local function unop_range(op, rhs)
      if op == 'ntohs' then return Range(0, 0xffff) end
      if op == 'ntohl' then return Range(INT32_MIN, INT32_MAX) end
      if op == 'uint32' then return Range(0, 2^32) end
      if op == 'int32' then return rhs:tobit() end
      error('unexpected op '..op)
   end
   local function binop_range(op, lhs, rhs)
      if op == '+' then return lhs:add(rhs) end
      if op == '-' then return lhs:sub(rhs) end
      if op == '*' then return lhs:mul(rhs) end
      if op == '*64' then return lhs:mul64(rhs) end
      if op == '/' then return lhs:div(rhs) end
      if op == '&' then return lhs:band(rhs) end
      if op == '|' then return lhs:bor(rhs) end
      if op == '^' then return lhs:bxor(rhs) end
      if op == '<<' then return lhs:lshift(rhs) end
      if op == '>>' then return lhs:rshift(rhs) end
      error('unexpected op '..op)
   end

   local function visit(expr, db_t, db_f)
      if type(expr) ~= 'table' then return expr end
      local op = expr[1]

      -- Logical ops add to their db_t and db_f stores.
      if relops[op] then
         local db = push(db_t)
         local lhs, rhs = visit(expr[2], db), visit(expr[3], db)
         merge(db_t, car(db))
         merge(db_f, car(db))
         local function fold(l, r)
            return { assert(folders[op])(l, r) and 'true' or 'false' }
         end
         local lhs_range, rhs_range = lookup(db_t, lhs), lookup(db_t, rhs)
         -- If we folded both sides, or if the ranges are strictly
         -- ordered, the condition will fold.
         if ((lhs_range:fold() and rhs_range:fold())
             or lhs_range:lt(rhs_range) or lhs_range:gt(rhs_range)) then
            return fold(lhs_range:min(), rhs_range:min())
         elseif (lhs_range:max() == rhs_range:min() and op == '<='
                 or lhs_range:min() == rhs_range:max() and op == '>=') then
            -- The ranges are ordered, but not strictly, and in the same
            -- sense as the test: the condition is true.
            return { 'true' }
         end
         -- Otherwise, the relop may restrict the ranges for both
         -- arguments along both continuations.
         local lhs_range_t, lhs_range_f, rhs_range_t, rhs_range_f =
            branch_ranges(op, lhs_range, rhs_range)
         restrict(db_t, lhs, lhs_range_t)
         restrict(db_f, lhs, lhs_range_f)
         restrict(db_t, rhs, rhs_range_t)
         restrict(db_f, rhs, rhs_range_f)
         return { op, lhs, rhs }
      elseif simple[op] then
         return expr
      elseif op == 'if' then
         local test, t, f = expr[2], expr[3], expr[4]

         local test_db_t, test_db_f = push(db_t), push(db_t)
         test = visit(test, test_db_t, test_db_f)

         local kt_db_t, kt_db_f = push(test_db_t), push(test_db_t)
         local kf_db_t, kf_db_f = push(test_db_f), push(test_db_f)
         t = visit(t, kt_db_t, kt_db_f)
         f = visit(f, kf_db_t, kf_db_f)

         if tailops[t[1]] then
            local head_t, head_f = car(kf_db_t), car(kf_db_f)
            local assertions = cadr(kf_db_t)
            merge(db_t, assertions)
            merge(db_t, head_t)
            merge(db_f, assertions)
            merge(db_f, head_f)
         elseif tailops[f[1]] then
            local head_t, head_f = car(kt_db_t), car(kt_db_f)
            local assertions = cadr(kt_db_t)
            merge(db_t, assertions)
            merge(db_t, head_t)
            merge(db_f, assertions)
            merge(db_f, head_f)
         else
            local head_t_t, head_t_f = car(kt_db_t), car(kt_db_f)
            local head_f_t, head_f_f = car(kf_db_t), car(kf_db_f)
            -- union the assertions?
            union(db_t, head_t_t, head_f_t)
            union(db_f, head_t_f, head_f_f)
         end
         return { op, test, t, f }
      elseif op == 'call' then
         return expr
      else
         -- An arithmetic op, which interns into the fresh table pushed
         -- by the containing relop.
         local db = db_t
         if op == '[]' then
            local pos, size = visit(expr[2], db), expr[3]
            local ret = { op, pos, size }
            local size_max
            if size == 1 then size_max = 0xff
            elseif size == 2 then size_max = 0xffff
            else size_max = 0xffffffff end
            local range = lookup(db, ret):restrict(Range(0, size_max))
            return define(db, ret, range)
         elseif unops[op] then
            local rhs = visit(expr[2], db)
            local rhs_range = lookup(db, rhs)
            if rhs_range:fold() then
               return assert(folders[op])(rhs_range:fold())
            end
            if (op == 'uint32' and 0 <= rhs_range:min()
                and rhs_range:max() <= UINT32_MAX) then
               return rhs
            elseif (op == 'int32' and INT32_MIN <= rhs_range:min()
                and rhs_range:max() <= INT32_MAX) then
               return rhs
            end
            local range = unop_range(op, rhs_range)
            return restrict(db, { op, rhs }, range)
         elseif binops[op] then
            local lhs, rhs = visit(expr[2], db), visit(expr[3], db)
            if type(lhs) == 'number' and type(rhs) == 'number' then
               return assert(folders[op])(lhs, rhs)
            end
            local lhs_range, rhs_range = lookup(db, lhs), lookup(db, rhs)
            local range = binop_range(op, lhs_range, rhs_range)
            return restrict(db, { op, lhs, rhs }, range)
         else
            error('what is this '..op)
         end
      end
   end
   return visit(expr, push(), push())
end

-- Length assertion hoisting.
local function lhoist(expr, db)
   -- Recursively annotate the logical expressions in EXPR, returning
   -- tables of the form { MIN_T, MIN_F, MIN_PASS, MAX_FAIL, EXPR }.
   -- MIN_T indicates that for this expression to be true, the packet
   -- must be at least as long as MIN_T.  Similarly for MIN_F.  MIN_PASS
   -- means that if the packet is smaller than MIN_PASS then the filter
   -- will definitely fail.  MAX_FAIL means that if the packet is
   -- smaller than MAX_FAIL, there is a 'fail' call on some path.
   local function annotate(expr, is_tail)
      local function aexpr(min_t, min_f, min_pass, max_fail, expr)
         if is_tail then
            min_pass = math.max(min_pass, min_t)
            min_t = min_pass
         end
         return { min_t, min_f, min_pass, max_fail, expr }
      end
      local op = expr[1]
      if (op == '>=' and expr[2] == 'len' and type(expr[3]) == 'number') then
         return aexpr(expr[3], 0, 0, -1, expr)
      elseif op == 'if' then
         local test, t, f = expr[2], expr[3], expr[4]
         local test_a = annotate(test, false)
         local t_a, f_a = annotate(t, is_tail), annotate(f, is_tail)
         local test_min_t, test_min_f = test_a[1], test_a[2]
         local test_min_pass, test_max_fail = test_a[3], test_a[4]
         local function if_bool_mins()
            local t, f = t[1], f[1]
            local function branch_bool_mins(abranch, min)
               local branch_min_t, branch_min_f = abranch[1], abranch[2]
               return math.max(branch_min_t, min), math.max(branch_min_f, min)
            end
            local t_min_t, t_min_f = branch_bool_mins(t_a, test_min_t)
            local f_min_t, f_min_f = branch_bool_mins(f_a, test_min_f)
            if trueops[t] then t_min_f = f_min_f end
            if trueops[f] then f_min_f = t_min_f end
            if t == 'fail' then return f_min_t, f_min_f end
            if f == 'fail' then return t_min_t, t_min_f end
            if t == 'false' then t_min_t = f_min_t end
            if f == 'false' then f_min_t = t_min_t end
            return math.min(t_min_t, f_min_t), math.min(t_min_f, f_min_f)
         end
         local function if_fail_mins()
            local t, f = t[1], f[1]
            local min_pass, max_fail
            local t_min_pass, t_max_fail = t_a[3], t_a[4]
            local f_min_pass, f_max_fail = f_a[3], f_a[4]
            -- Four cases: both T and F branches are fail; one of them
            -- is a fail; neither are fails.
            if t == 'fail' then
               if f == 'fail' then
                  min_pass = test_min_pass
                  max_fail = UINT16_MAX
               else
                  min_pass = math.max(test_min_f, f_min_pass, test_min_pass)
                  max_fail = math.max(test_min_t, f_max_fail, test_max_fail)
               end
            elseif f == 'fail' then
               min_pass = math.max(test_min_t, t_min_pass, test_min_pass)
               max_fail = math.max(test_min_f, f_max_fail, test_max_fail)
            else
               min_pass = math.max(test_min_pass, math.min(t_min_pass, f_min_pass))
               max_fail = math.max(t_max_fail, f_max_fail, test_max_fail)
            end
            return min_pass, max_fail
         end
         local min_t, min_f = if_bool_mins()
         local min_pass, max_fail = if_fail_mins()
         return aexpr(min_t, min_f, min_pass, max_fail, { op, test_a, t_a, f_a })
      else
         return aexpr(0, 0, 0, -1, expr)
      end
   end

   -- Strip the annotated expression AEXPR.  Whenever the packet needs
   -- be longer than the MIN argument, insert a length check and revisit
   -- with the new MIN.  Elide other length checks.
   local function reduce(aexpr, min, is_tail)
      local min_t, min_f, min_pass, max_fail, expr =
         aexpr[1], aexpr[2], aexpr[3], aexpr[4], aexpr[5]

      -- Reject any packets that are too short to pass.
      if is_tail then min_pass = math.max(min_pass, min_t) end
      if min < min_pass then
         local expr = reduce(aexpr, min_pass, is_tail)
         return { 'if', { '>=', 'len', min_pass }, expr, { 'fail' } }
      end

      -- Hoist length checks if we know a packet must be of a certain
      -- length for the expression to be true, and we are certain that
      -- we aren't going to hit a "fail".
      if min < min_t and max_fail < min then
         local expr = reduce(aexpr, min_t, is_tail)
         return { 'if', { '>=', 'len', min_t }, expr, { 'false' } }
      end

      local op = expr[1]
      if op == 'if' then
         local t = reduce(expr[2], min, false)
         local kt = reduce(expr[3], min, is_tail)
         local kf = reduce(expr[4], min, is_tail)
         return { op, t, kt, kf }
      elseif op == '>=' and expr[2] == 'len' and type(expr[3]) == 'number' then
         -- min may be set conservatively low; it is *only* a lower bound.
         -- If expr[3] is <= min, { 'true' } is a valid optimization.
         -- Otherwise, there's not enough information; leave expr alone.
         if expr[3] <= min then return { 'true' } else return expr end
      else
         return expr
      end
   end
      
   return reduce(annotate(expr, true), 0, true)
end

function optimize_inner(expr)
   expr = simplify(expr, true)
   expr = simplify(cfold(expr, {}), true)
   expr = simplify(infer_ranges(expr), true)
   expr = simplify(lhoist(expr), true)
   clear_cache()
   return expr
end

function optimize(expr)
   expr = utils.fixpoint(optimize_inner, expr)
   if verbose then pp(expr) end
   return expr
end

function selftest ()
   print("selftest: pf.optimize")
   local parse = require('pf.parse').parse
   local expand = require('pf.expand').expand
   local function opt(str) return optimize(expand(parse(str), "EN10MB")) end
   local equals, assert_equals = utils.equals, utils.assert_equals
   assert_equals({ 'fail' },
      opt("1 = 2"))
   assert_equals({ '=', "len", 1 },
      opt("1 = len"))
   assert_equals({ 'match' },
      opt("1 = 2/2"))
   assert_equals({ 'if', { '>=', 'len', 1},
                   { '=', { '[]', 0, 1 }, 2 },
                   { 'fail' }},
      opt("ether[0] = 2"))
   assert_equals({ 'if', { '>=', 'len', 7},
                   { '<',
                     { '+', { '+', { '[]', 5, 1 }, { '[]', 6, 1 } }, 3 },
                     10 },
                   { 'fail' }},
      opt("(ether[5] + 1) + (ether[6] + 2) < 10"))
   assert_equals({ 'if', { '>=', 'len', 7},
                   { '<',
                     { '+', { '+', { '[]', 5, 1 }, { '[]', 6, 1 } }, 3 },
                     10 },
                   { 'fail' }},
      opt("ether[5] + 1 + ether[6] + 2 < 10"))
   assert_equals({ '>=', 'len', 2},
      opt("greater 1 and greater 2"))
   -- Could check this, but it's very large
   opt("tcp port 80 and (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)")
   opt("tcp port 5555")
   print("OK")
end
