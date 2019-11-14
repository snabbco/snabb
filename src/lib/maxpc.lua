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


-- digit parsing

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


-- string parsing

function match.string (s)
   local chars = {}
   for i = 1, #s do
      chars[i] = match.equal(s:sub(i,i))
   end
   return match.seq(unpack(chars))
end


-- backtracking combinators

function match.plus (a, b)
   return function (s)
      local a_more, b_more, more
      a_more = function () return a(s) end
      more = function ()
         if b_more then
            local rest
            rest, _, _, b_more = b_more()
            if rest then
               return rest, nil, nil, more
            else
               return more()
            end
         elseif a_more then
            local suffix
            suffix, _, _, a_more = a_more()
            if suffix then
               b_more = function () return b(suffix) end
               return more()
            end
         end
      end
      return more()
   end
end

function match.alternate (x, y)
   return function (s)
      local x_more, more
      x_more = function ()
         return x(s)
      end
      more = function ()
         local rest
         if x_more then
            rest, _, _, x_more = x_more()
         end
         if rest then
            return rest, nil, nil, more
         else
            return y(s)
         end
      end
      return more()
   end
end

function match.optional (parser)
   return match.alternate(parser, match.seq())
end

function match.all (parser)
   return match.optional(
      match.plus(parser, function (s) return match.all(parser)(s) end)
   )
end

local function reduce (fun, tab)
   local acc
   for _, val in ipairs(tab) do
      if not acc then acc = val
      else            acc = fun(acc, val) end
   end
   return acc
end

local function identity (...) return ... end
local function constantly_nil () end

function match.path (...)
   local parsers = {...}
   if #parsers > 0 then
      return reduce(match.plus, parsers)
   else
      return identity
   end
end

function match.either (...)
   local parsers = {...}
   if #parsers > 0 then
      return reduce(match.alternate, parsers)
   else
      return constantly_nil
   end
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

   local function is_digit (x)
      return ("01234567890"):find(x, 1, true)
   end

   -- match.satisfied
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

   local function is_alphanumeric (x)
      return ("01234567890abcdefghijklmnopqrstuvwxyz"):find(x, 1, true)
   end

   -- combine._and
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

   -- digits
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

   -- backtracking
   local result, matched, eof =
      parse("a", match.either(match.equal("a"), match.equal("b")))
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof =
      parse("b", match.either(match.equal("a"), match.equal("b")))
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof = parse(".", match.optional(match.equal(".")))
   assert(not result) assert(matched)
   local result, matched, eof = parse("", match.optional(match.equal(".")))
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof = parse(
      "0aaaaaaaa1",
      match.path(match.equal("0"),
                 match.all(match.satisfies(is_alphanumeric)),
                 match.equal("1"))
   )
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof = parse(
      "aaac",
      match.path(
         match.all(
            match.either(
               match.seq(match.equal("a"), match.equal("a")),
               match.seq(match.equal("a"), match.equal("a"), match.equal("a")),
               match.equal("c")
            )
         ),
         match.eof()
      )
   )
   assert(not result) assert(matched) assert(eof)
   local domain_like = match.either(
      match.path(
         match.path(
            match.all(match.path(match.all(match.satisfies(is_alphanumeric)),
                                 combine.diff(match.satisfies(is_alphanumeric),
                                              match.satisfies(is_digit)),
                                 match.equal(".")))
         ),
         match.path(match.all(match.satisfies(is_alphanumeric)),
                    combine.diff(match.satisfies(is_alphanumeric),
                                 match.satisfies(is_digit)),
                    match.optional(match.equal("."))),
         match.eof()
      ),
      match.seq(match.equal("."), match.eof())
   )
   local result, matched, eof = parse(".", domain_like)
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof = parse("foo.", domain_like)
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof = parse("1foo.bar", domain_like)
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof = parse("foo.b2ar.baz", domain_like)
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof = parse("foo.bar.2baz.", domain_like)
   assert(not result) assert(matched) assert(eof)
   local result, matched, eof = parse("foo2", domain_like)
   assert(not result) assert(not matched) assert(not eof)
   local result, matched, eof = parse("..", domain_like)
   assert(not result) assert(not matched) assert(not eof)
   local result, matched, eof = parse("123.456", domain_like)
   assert(not result) assert(not matched) assert(not eof)
end
