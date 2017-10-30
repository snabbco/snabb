-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- “XSD types” regular expression implementation (ASCII only), see:
-- https://www.w3.org/TR/xmlschema11-2/#regexs
module(..., package.seeall)

local maxpc = require("lib.maxpc")
local match, capture, combine = maxpc.import()

function capture.regExp ()
   return capture.unpack(
      capture.seq(capture.branch(), combine.any(capture.otherBranch())),
      function (branch, otherBranches)
         local branches = {branch}
         for _, branch in ipairs(otherBranches or {}) do
            table.insert(branches, branch)
         end
         return {branches=branches}
      end
   )
end

function capture.branch ()
   return capture.transform(combine.any(capture.piece()),
                            function (pieces) return {pieces=pieces} end)
end

function capture.otherBranch ()
   return capture.unpack(
      capture.seq(match.equal("|"), capture.branch()),
      function (_, branch) return branch end
   )
end

function capture.piece ()
   return capture.unpack(
      capture.seq(capture.atom(), combine.maybe(capture.quantifier())),
      function (atom, quantifier)
         return {atom=atom, quantifier=quantifier or nil}
      end
   )
end

function capture.quantifier ()
   return combine._or(
      capture.subseq(match.equal("?")),
      capture.subseq(match.equal("*")),
      capture.subseq(match.equal("+")),
      capture.unpack(
         capture.seq(match.equal("{"), capture.quantity(), match.equal("}")),
         function (_, quantity, _) return quantity end
      )
   )
end

function match.digit (s)
   return match.satisfies(
      function (s)
         return ("0123456789"):find(s, 1, true)
      end
   )
end

function capture.quantity ()
   return combine._or(
      capture.quantRange(),
      capture.quantMin(),
      capture.transform(capture.quantExact(),
                        function (n) return {exactly=n} end)
   )
end

function capture.quantRange ()
   return capture.unpack(
      capture.seq(capture.quantExact(),
                  match.equal(","),
                  capture.quantExact()),
      function (min, _, max) return {min=min, max=max} end
   )
end

function capture.quantMin ()
   return capture.unpack(
      capture.seq(capture.quantExact(), match.equal(",")),
      function (min, _) return {min=min} end
   )
end

function capture.quantExact ()
   return capture.transform(
      capture.subseq(combine.some(match.digit())),
      tonumber
   )
end

function capture.atom ()
   return combine._or(
      capture.NormalChar(),
      capture.charClass(),
      capture.subExp()
   )
end

local regExp_parser -- forward definition
local function regExp_binding (s) return regExp_parser(s) end

function capture.subExp ()
   return capture.unpack(
      capture.seq(match.equal('('), regExp_binding, match.equal(')')),
      function (_, expression, _) return expression end
   )
end

function match.MetaChar ()
   return match.satisfies(
      function (s)
         return (".\\?*+{}()|[]"):find(s, 1, true)
      end
   )
end

function match.NormalChar (s)
   return match._not(match.MetaChar())
end

function capture.NormalChar ()
   return capture.subseq(match.NormalChar())
end

function capture.charClass ()
   return combine._or(
      capture.SingleCharEsc(),
      capture.charClassEsc(),
      capture.charClassExpr(),
      capture.WildcardEsc()
   )
end

function capture.charClassExpr ()
   return capture.unpack(
      capture.seq(match.equal("["), capture.charGroup(), match.equal("]")),
      function (_, charGroup, _) return charGroup end
   )
end

function capture.charGroup ()
   return capture.unpack(
      capture.seq(
         combine._or(capture.negCharGroup(), capture.posCharGroup()),
         combine.maybe(capture.charClassSubtraction())
      ),
      function (group, subtract)
         return {class=group, subtract=subtract or nil}
      end
   )
end

local charClassExpr_parser -- forward declaration
local function charClassExpr_binding (s)
   return charClassExpr_parser(s)
end

function capture.charClassSubtraction ()
   return capture.unpack(
      capture.seq(match.equal("-"), charClassExpr_binding),
      function (_, charClassExpr, _) return charClassExpr end
   )
end

function capture.posCharGroup ()
   return capture.transform(
      combine.some(capture.charGroupPart()),
      function (parts) return {include=parts} end
   )
end

function capture.negCharGroup ()
   return capture.unpack(
      capture.seq(match.equal("^"), capture.posCharGroup()),
      function (_, group) return {exclude=group.include} end
   )
end

function capture.charGroupPart ()
   return combine._or(
      capture.charClassEsc(),
      capture.charRange(),
      capture.singleChar()
   )
end

function capture.singleChar ()
   return combine._or(capture.SingleCharEsc(), capture.singleCharNoEsc())
end

function capture.charRange ()
   local rangeChar = combine.diff(capture.singleChar(), match.equal("-"))
   return capture.unpack(
      capture.seq(rangeChar, match.equal("-"), rangeChar),
      function (from, _, to) return {range={from,to}} end
   )
end

function capture.singleCharNoEsc ()
   local function is_singleCharNoEsc (s)
      return not ("[]"):find(s, 1, true)
   end
   return combine.diff(
      capture.subseq(match.satisfies(is_singleCharNoEsc)),
      -- don’t match the "-" leading a character class subtraction
      match.seq(match.equal("-"), match.equal("["))
   )
end

function capture.charClassEsc ()
   return combine._or(
      capture.MultiCharEsc() --, capture.catEsc(), capture.complEsc()
   )
end

function capture.SingleCharEsc ()
   local function is_SingleCharEsc (s)
      return ("nrt\\|.?*+(){}-[]^"):find(s, 1, true)
   end
   return capture.unpack(
      capture.seq(
         match.equal("\\"),
         capture.subseq(match.satisfies(is_SingleCharEsc))
      ),
      function (_, char) return {escape=char} end
   )
end

-- NYI: catEsc, complEsc

function capture.MultiCharEsc ()
   local function is_multiCharEsc (s)
      return ("sSiIcCdDwW"):find(s, 1, true)
   end
   return capture.unpack(
      capture.seq(
         match.equal("\\"),
         capture.subseq(match.satisfies(is_multiCharEsc))
      ),
      function (_, char) return {escape=char} end
   )
end

function capture.WildcardEsc ()
   return capture.transform(
      match.equal("."),
      function (_) return {escape="."} end
   )
end

regExp_parser = capture.regExp()
charClassExpr_parser = capture.charClassExpr()

function parse (expr)
   local result, success, is_eof = maxpc.parse(expr, regExp_parser)
   return (success and is_eof and result) or nil
end
