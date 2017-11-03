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

input = {}

function input.new (str)
   return { idx = 1, str = str }
end

function input.empty (s)
   return s.idx > #s.str
end

function input.first (s, n)
   return s.str:sub(s.idx, s.idx + (n or 1) - 1)
end

function input.rest (s)
   return { idx = s.idx + 1, str = s.str }
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
   local function constantly_nil ()
      return nil
   end
   return combine.diff(
      capture.transform(capture.element(), constantly_nil),
      parser
   )
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
   parse(":a:b", capture.unpack(capture.seq(match.equal("_"),
                                            capture.element(),
                                            match.equal("_"),
                                            capture.element()),
                                function (_, a, _, b)
                                   assert(a == "a")
                                   assert(b == "b")
                                end
   ))
end
