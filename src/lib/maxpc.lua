-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Max’s parser combinators (for Lua)
module(..., package.seeall)


-- interface

-- use like this:
--   local match, capture, combine = require("lib.maxpc").import()
function import ()
   local l_match, l_capture, l_combine = {}, {}, {}
   for key, value in pairs(match) do
      l_match[key] = value
   end
   for key, value in pairs(capture) do
      l_capture[key] = value
   end
   for key, value in pairs(combine) do
      l_combine[key] = value
   end
   return l_match, l_capture, l_combine
end

-- parse(str, parser) => result_value, was_successful, has_reached_eof
function parse (str, parser)
   local rest, value = parser(input.new(str))
   return value, rest and true, #str == 0 or (rest and input.empty(rest))
end


-- input protocol

-- NB: its trivial to support *both* octet and UTF-8 input, see
--  commit 085a5813473f1fa64502b480cc00122bef0fb32a

input = {}

function input.new (str)
   return { pos = 1, idx = 1, str = str }
end

function input.empty (s)
   return s.idx > #s.str
end

function input.first (s, n) n = n or 1
   local to = utf8next(s.str, s.idx)
   while n > 1 do n, to = n - 1, utf8next(s.str, to) end
   return s.str:sub(s.idx, to - 1)
end

function input.rest (s)
   return { pos = s.pos + 1, idx = utf8next(s.str, s.idx), str = s.str }
end

function input.position (s)
   return s.idx
end


-- primitives

capture, match, combine = {}, {}, {}

function match.eof ()
   return function (s)
      if input.empty(s) then
         return s
      end
   end
end

function capture.element ()
   return function (s)
      if not input.empty(s) then
         return input.rest(s), input.first(s), true
      end
   end
end

function match.fail (handler)
   return function (s)
      if handler then
         handler(input.position(s))
      end
   end
end

function match.satisfies (test, parser)
   parser = parser or capture.element()
   return function (s)
      local rest, value = parser(s)
      if rest and test(value) then
         return rest
      end
   end
end

function capture.subseq (parser)
   return function (s)
      local rest = parser(s)
      if rest then
         local diff = input.position(rest) - input.position(s)
         return rest, input.first(s, diff), true
      end
   end
end

function match.seq (...)
   local parsers = {...}
   return function (s)
      for _, parser in ipairs(parsers) do
         s = parser(s)
         if not s then
            return
         end
      end
      return s
   end
end

function capture.seq (...)
   local parsers = {...}
   return function (s)
      local seq = {}
      for _, parser in ipairs(parsers) do
         local rest, value = parser(s)
         if rest then
            table.insert(seq, value or false)
            s = rest
         else
            return
         end
      end
      return s, seq, true
   end
end

function combine.any (parser)
   return function (s)
      local seq = {}
      while true do
         local rest, value, present = parser(s)
         if rest then
            s = rest
         else
            local value
            if #seq > 0 then
               value = seq
            end
            return s, value, value ~= nil
         end
         if present then
            table.insert(seq, value or false)
         end
      end
   end
end

function combine._or (...)
   local parsers = {...}
   return function (s)
      for _, parser in ipairs(parsers) do
         local rest, value, present = parser(s)
         if rest then
            return rest, value, present
         end
      end
   end
end

function combine._and (...)
   local parsers = {...}
   return function (s)
      local rest, value, present
      for _, parser in ipairs(parsers) do
         rest, value, present = parser(s)
         if not rest then
            return
         end
      end
      return rest, value, present
   end
end

function combine.diff (parser, ...)
   local punion = combine._or(...)
   return function (s)
      if not punion(s) then
         return parser(s)
      end
   end
end

function capture.transform (parser, transform)
   return function (s)
      local rest, value = parser(s)
      if rest then
         return rest, transform(value), true
      end
   end
end


-- built-in combinators

function combine.maybe (parser)
   return combine._or(parser, match.seq())
end

function match._not (parser)
   local function constantly_true () return true end
   return combine.diff(match.satisfies(constantly_true), parser)
end

function combine.some (parser)
   return combine._and(parser, combine.any(parser))
end

function match.equal (x, parser)
   local function is_equal_to_x (y)
      return x == y
   end
   return match.satisfies(is_equal_to_x, parser)
end

function capture.unpack (parser, f)
   local function destructure (seq)
      return f(unpack(seq))
   end
   return capture.transform(parser, destructure)
end


-- Digit parsing

function match.digit (radix)
   radix = radix or 10
   local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
   assert(radix >= 2 and radix <= 36)
   return match.satisfies(
      function (s)
         return digits:sub(1, radix):find(s:lower(), 1, true)
      end
   )
end

function capture.natural_number (radix)
   return capture.transform(
      capture.subseq(combine.some(match.digit(radix))),
      function (s) return tonumber(s, radix) end
   )
end

function capture.sign ()
   local function is_sign (s) return s == "+" or s == "-" end
   return combine._and(match.satisfies(is_sign), capture.element())
end

function capture.integer_number (radix)
   return capture.unpack(
      capture.seq(combine.maybe(capture.sign()),
                  capture.natural_number(radix)),
      function (sign, number)
         if sign == "-" then number = -number end
         return number
      end
   )
end


-- UTF-8 decoding (see http://nullprogram.com/blog/2017/10/06/)

local bit = require("bit")
local lshift, rshift, band, bor = bit.lshift, bit.rshift, bit.band, bit.bor

function utf8length (str, idx) idx = idx or 1
   local lengths = {
      1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
      0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 3, 3, 4, 0
   }
   return lengths[rshift(str:byte(idx), 3) + 1]
end

function utf8next (str, idx) idx = idx or 1
   return idx + math.max(utf8length(str, idx), 1) -- advance even on error
end

function codepoint (str, idx) idx = idx or 1
   local length = utf8length(str, idx)
   local point
   if     length == 1 then point = str:byte(idx)
   elseif length == 2 then point = bor(lshift(band(str:byte(idx), 0x1f), 6),
                                       band(str:byte(idx+1), 0x3f))
   elseif length == 3 then point = bor(lshift(band(str:byte(idx), 0x0f), 12),
                                       lshift(band(str:byte(idx+1), 0x3f), 6),
                                       band(str:byte(idx+2), 0x3f))
   elseif length == 4 then point = bor(lshift(band(str:byte(idx), 0x07), 18),
                                       lshift(band(str:byte(idx+1), 0x3f), 12),
                                       lshift(band(str:byte(idx+2), 0x3f), 6),
                                       band(str:byte(idx+3), 0x3f))
   else
      point = -1 -- invalid
   end
   if point >= 0xd800 and point <= 0xdfff then
      point = -1 -- surrogate half
   end
   return point
end


-- tests

function selftest ()
   local lib = require("core.lib")

   -- match.eof
   local result, matched, eof = parse("", match.eof())
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof = parse("f", match.eof())
   assert(not result) assert(not matched) assert(not eof)

   -- match.fail
   local result, matched, eof = parse("f", match.fail())
   assert(not result) assert(not matched) assert(not eof)
   local result, matched, eof = parse("f", combine.maybe(match.fail()))
   assert(not result) assert(matched) assert(not eof)
   local success, err = pcall(parse, "", match.fail(
                                 function (pos)
                                    error(pos .. ": fail")
                                 end
   ))
   assert(not success) assert(err:find("1: fail", 1, true))

   -- capture.element
   local result, matched, eof = parse("foo", capture.element())
   assert(result == "f") assert(matched) assert(not eof)
   local result, matched, eof = parse("", capture.element())
   assert(not result) assert(not matched) assert(eof)

   -- match.satisfied
   local function is_digit (x)
      return ("01234567890"):find(x, 1, true)
   end
   local result, matched, eof =
      parse("123", capture.subseq(match.satisfies(is_digit)))
   assert(result == "1") assert(matched) assert(not eof)
   local result, matched, eof = parse("foo", match.satisfies(is_digit))
   assert(not result) assert(not matched) assert(not eof)

   -- match.seq
   local result, matched, eof = parse("fo", match.seq(capture.element(),
                                                      capture.element(),
                                                      match.eof()))
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof = parse("foo", match.seq(capture.element(),
                                                       capture.element(),
                                                       match.eof()))
   assert(not result) assert(not matched) assert(not eof)
   local result, matched, eof =
      parse("fo", match.seq(match.seq(match.equal("f"), capture.element()),
                            match.eof()))
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof = parse("", match.seq())
   assert(not result) assert(matched) assert(eof)

   -- capture.seq
   local result, matched, eof = parse("fo", capture.seq(capture.element(),
                                                        capture.element(),
                                                        match.eof()))
   assert(lib.equal(result, {"f", "o", false})) assert(matched) assert(eof)
   local result, matched, eof = parse("foo", capture.seq(capture.element(),
                                                         capture.element(),
                                                         match.eof()))
   assert(not result) assert(not matched) assert(not eof)
   local result, matched, eof =
      parse("fo", capture.seq(match.seq(match.equal("f"), capture.element()),
                              match.eof()))
   assert(result) assert(matched) assert(eof)
   local result, matched, eof = parse("", capture.seq())
   assert(result) assert(matched) assert(eof)

   -- combine.any
   local result, matched, eof = parse("", combine.any(capture.element()))
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof =
      parse("123foo", capture.subseq(combine.any(match.satisfies(is_digit))))
   assert(result == "123") assert(matched) assert(not eof)
   local result, matched, eof = parse("", combine.some(capture.element()))
   assert(not result) assert(not matched) assert(eof)
   local result, matched, eof =
      parse("foo", capture.seq(combine.some(capture.element()), match.eof()))
   assert(lib.equal(result, {{"f","o","o"},false})) assert(matched) assert(eof)

   -- combine._or
   local fo = combine._or(match.equal("f"), match.equal("o"))
   local result, matched, eof = parse("fo", capture.seq(fo, fo, match.eof()))
   assert(result) assert(matched) assert(eof)
   local result, matched, eof = parse("x", fo)
   assert(not result) assert(not matched) assert(not eof)
   local result, matched, eof = parse("", fo)
   assert(not result) assert(not matched) assert(eof)

   -- combine._and
   local function is_alphanumeric (x)
      return ("01234567890abcdefghijklmnopqrstuvwxyz"):find(x, 1, true)
   end
   local d = combine._and(match.satisfies(is_alphanumeric),
                          match.satisfies(is_digit))
   local result, matched, eof = parse("12", capture.seq(d, d, match.eof()))
   assert(result) assert(matched) assert(eof)
   local result, matched, eof = parse("f", capture.seq(d, match.eof()))
   assert(not result) assert(not matched) assert(not eof)
   local result, matched, eof = parse("x1", capture.seq(d, d))
   assert(not result) assert(not matched) assert(not eof)

   -- combine.diff
   local ins = combine.diff(match.satisfies(is_alphanumeric), match.equal("c"))
   local result, matched, eof = parse("fo", capture.seq(ins, ins, match.eof()))
   assert(result) assert(matched) assert(eof)
   local result, matched, eof = parse("c", capture.seq(ins))
   assert(not result) assert(not matched) assert(not eof)
   local result, matched, eof = parse("ac", capture.seq(ins, ins))
   assert(not result) assert(not matched) assert(not eof)
   local result, matched, eof =
      parse("f", capture.seq(match._not(match.eof()), match.eof()))
   assert(result) assert(matched) assert(eof)
   local result, matched, eof =
      parse("foo", combine.any(match._not(match.eof())))
   assert(not result) assert(matched) assert(eof)

   -- capture.transform
   parse("foo", capture.transform(match.fail(), error))
   local function constantly_true () return true end
   local result, matched, eof =
      parse("", capture.transform(match.eof(), constantly_true))
   assert(result) assert(matched) assert(eof)
   parse("_abce", capture.unpack(combine.any(capture.element()),
                                 function (_, a, b, c)
                                    assert(a == "a")
                                    assert(b == "b")
                                    assert(c == "c")
                                 end
   ))
   parse(":a:b", capture.unpack(capture.seq(match.equal(":"),
                                            capture.element(),
                                            match.equal(":"),
                                            capture.element()),
                                function (_, a, _, b)
                                   assert(a == "a")
                                   assert(b == "b")
                                end
   ))

   local result, matched, eof = parse("f", match.digit(16))
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof = parse("f423", capture.natural_number(16))
   assert(result == 0xf423) assert(matched) assert(eof)
   local result, matched, eof = parse("f423", capture.integer_number(16))
   assert(result == 0xf423) assert(matched) assert(eof)
   local result, matched, eof = parse("+f423", capture.integer_number(16))
   assert(result == 0xf423) assert(matched) assert(eof)
   local result, matched, eof = parse("-f423", capture.integer_number(16))
   assert(result == -0xf423) assert(matched) assert(eof)
   local result, matched, eof = parse("a1234", capture.integer_number())
   assert(not result) assert(not matched) assert(not eof)
   local result, matched, eof = parse("1234a", capture.integer_number())
   assert(result == 1234) assert(matched) assert(not eof)

   -- test UTF-8 input
   local result, matched, eof = parse("λ", capture.element())
   assert(result == "λ") assert(matched) assert(eof)
end
