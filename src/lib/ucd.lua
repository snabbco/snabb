-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local lib = require("core.lib")
local maxpc = require("lib.maxpc")
local codepoint = maxpc.codepoint
local match, capture, combine = maxpc.import()

function load_ucd (txt)
   local parser = capture.unpack(
      capture.seq(
         match.equal("\n"),
         capture.natural_number(16),
         combine.maybe(
            capture.unpack(
               capture.seq(
                  match.equal("."), match.equal("."),
                  capture.natural_number(16)
               ),
               function (_, _, stop) return stop end
            )
         ),
         combine.any(match.equal(" ")),
         match.equal(";"),
         combine.any(match.equal(" ")),
         capture.subseq(
            combine.some(
               match._not(
                  match.seq(combine.any(match.equal(" ")),
                            combine._or(match.equal("#"),
                                        match.equal("\n")))
               )
            )
         )
      ),
      function (_, start, stop, _, _, _, value)
         return {start=start, stop=stop, value=value}
      end
   )
   return maxpc.parse(
      lib.readfile(txt, "*a"),
      combine.any(
         capture.unpack(
            capture.seq(combine.any(match._not(parser)), parser),
            function (_, mapping) return mapping end
         )
      )
   )
end

function block_name (name)
   return name:gsub("[ _-]", ""):lower()
end

function compile_block_predicates (ucd_path)
   print("block = {}")
   for _, block in ipairs(load_ucd(ucd_path.."/Blocks.txt")) do
      if not block.stop then
         print(("function block.%s (c) return c == %d end")
               :format(block_name(block.value), block.start))
      else
         print(("function block.%s (c) return %d <= c and c <= %d end")
               :format(block_name(block.value), block.start, block.stop))
      end
   end
end

local function restrict_to_ascii (entries)
   local for_ascii = {}
   for _, entry in ipairs(entries) do
      if entry.start <= 127 and (entry.stop or 0) <= 127 then
         table.insert(for_ascii, entry)
      end
   end
   return for_ascii
end

function compile_category_predicates (ucd_path)
   print("category = {}")
   local categories = {}
   local entries = load_ucd(ucd_path.."/extracted/DerivedGeneralCategory.txt")
   local ascii_entries = restrict_to_ascii(entries)
   for _, entry in ipairs(entries) do
      if not categories[entry.value] then categories[entry.value] = {} end
   end
   -- Compile predicates for ASCII only
   for _, entry in ipairs(ascii_entries) do
      table.insert(categories[entry.value], entry)
   end
   for cat, entries in pairs(categories) do
      print(("function category.%s (c)"):format(cat))
      for _, entry in ipairs(entries) do
         if not entry.stop then
            print(("   if c == %d then return true end")
                  :format(entry.start))
         else
            print(("   if %d <= c and c <= %d then return true end"):format(
                  entry.start, entry.stop))
         end
      end
      print("   return false end")
   end
   -- Compile super categories
   local super_categories = {}
   for cat, _ in pairs(categories) do
      local super = cat:sub(1,1)
      if not super_categories[super] then super_categories[super] = {} end
      table.insert(super_categories[super], "category."..cat)
   end
   for super, cats in pairs(super_categories) do
      print(("function category.%s (c)"):format(super))
      print(("   return %s(c) end"):format(table.concat(cats, "(c) or ")))
   end
end

function selftest ()
   local ucd_path = os.getenv("SNABB_UCD_PATH")
   if not ucd_path then main.exit(engine.test_skipped_code) end

   compile_block_predicates(ucd_path)
   print()
   compile_category_predicates(ucd_path)
end


-- Code below here is automatically generated (for Unicode 10.0.0) by the
-- functions above.

block = {}
function block.basiclatin (c) return 0 <= c and c <= 127 end
function block.latin1supplement (c) return 128 <= c and c <= 255 end
function block.latinextendeda (c) return 256 <= c and c <= 383 end
function block.latinextendedb (c) return 384 <= c and c <= 591 end
function block.ipaextensions (c) return 592 <= c and c <= 687 end
function block.spacingmodifierletters (c) return 688 <= c and c <= 767 end
function block.combiningdiacriticalmarks (c) return 768 <= c and c <= 879 end
function block.greekandcoptic (c) return 880 <= c and c <= 1023 end
function block.cyrillic (c) return 1024 <= c and c <= 1279 end
function block.cyrillicsupplement (c) return 1280 <= c and c <= 1327 end
function block.armenian (c) return 1328 <= c and c <= 1423 end
function block.hebrew (c) return 1424 <= c and c <= 1535 end
function block.arabic (c) return 1536 <= c and c <= 1791 end
function block.syriac (c) return 1792 <= c and c <= 1871 end
function block.arabicsupplement (c) return 1872 <= c and c <= 1919 end
function block.thaana (c) return 1920 <= c and c <= 1983 end
function block.nko (c) return 1984 <= c and c <= 2047 end
function block.samaritan (c) return 2048 <= c and c <= 2111 end
function block.mandaic (c) return 2112 <= c and c <= 2143 end
function block.syriacsupplement (c) return 2144 <= c and c <= 2159 end
function block.arabicextendeda (c) return 2208 <= c and c <= 2303 end
function block.devanagari (c) return 2304 <= c and c <= 2431 end
function block.bengali (c) return 2432 <= c and c <= 2559 end
function block.gurmukhi (c) return 2560 <= c and c <= 2687 end
function block.gujarati (c) return 2688 <= c and c <= 2815 end
function block.oriya (c) return 2816 <= c and c <= 2943 end
function block.tamil (c) return 2944 <= c and c <= 3071 end
function block.telugu (c) return 3072 <= c and c <= 3199 end
function block.kannada (c) return 3200 <= c and c <= 3327 end
function block.malayalam (c) return 3328 <= c and c <= 3455 end
function block.sinhala (c) return 3456 <= c and c <= 3583 end
function block.thai (c) return 3584 <= c and c <= 3711 end
function block.lao (c) return 3712 <= c and c <= 3839 end
function block.tibetan (c) return 3840 <= c and c <= 4095 end
function block.myanmar (c) return 4096 <= c and c <= 4255 end
function block.georgian (c) return 4256 <= c and c <= 4351 end
function block.hanguljamo (c) return 4352 <= c and c <= 4607 end
function block.ethiopic (c) return 4608 <= c and c <= 4991 end
function block.ethiopicsupplement (c) return 4992 <= c and c <= 5023 end
function block.cherokee (c) return 5024 <= c and c <= 5119 end
function block.unifiedcanadianaboriginalsyllabics (c) return 5120 <= c and c <= 5759 end
function block.ogham (c) return 5760 <= c and c <= 5791 end
function block.runic (c) return 5792 <= c and c <= 5887 end
function block.tagalog (c) return 5888 <= c and c <= 5919 end
function block.hanunoo (c) return 5920 <= c and c <= 5951 end
function block.buhid (c) return 5952 <= c and c <= 5983 end
function block.tagbanwa (c) return 5984 <= c and c <= 6015 end
function block.khmer (c) return 6016 <= c and c <= 6143 end
function block.mongolian (c) return 6144 <= c and c <= 6319 end
function block.unifiedcanadianaboriginalsyllabicsextended (c) return 6320 <= c and c <= 6399 end
function block.limbu (c) return 6400 <= c and c <= 6479 end
function block.taile (c) return 6480 <= c and c <= 6527 end
function block.newtailue (c) return 6528 <= c and c <= 6623 end
function block.khmersymbols (c) return 6624 <= c and c <= 6655 end
function block.buginese (c) return 6656 <= c and c <= 6687 end
function block.taitham (c) return 6688 <= c and c <= 6831 end
function block.combiningdiacriticalmarksextended (c) return 6832 <= c and c <= 6911 end
function block.balinese (c) return 6912 <= c and c <= 7039 end
function block.sundanese (c) return 7040 <= c and c <= 7103 end
function block.batak (c) return 7104 <= c and c <= 7167 end
function block.lepcha (c) return 7168 <= c and c <= 7247 end
function block.olchiki (c) return 7248 <= c and c <= 7295 end
function block.cyrillicextendedc (c) return 7296 <= c and c <= 7311 end
function block.sundanesesupplement (c) return 7360 <= c and c <= 7375 end
function block.vedicextensions (c) return 7376 <= c and c <= 7423 end
function block.phoneticextensions (c) return 7424 <= c and c <= 7551 end
function block.phoneticextensionssupplement (c) return 7552 <= c and c <= 7615 end
function block.combiningdiacriticalmarkssupplement (c) return 7616 <= c and c <= 7679 end
function block.latinextendedadditional (c) return 7680 <= c and c <= 7935 end
function block.greekextended (c) return 7936 <= c and c <= 8191 end
function block.generalpunctuation (c) return 8192 <= c and c <= 8303 end
function block.superscriptsandsubscripts (c) return 8304 <= c and c <= 8351 end
function block.currencysymbols (c) return 8352 <= c and c <= 8399 end
function block.combiningdiacriticalmarksforsymbols (c) return 8400 <= c and c <= 8447 end
function block.letterlikesymbols (c) return 8448 <= c and c <= 8527 end
function block.numberforms (c) return 8528 <= c and c <= 8591 end
function block.arrows (c) return 8592 <= c and c <= 8703 end
function block.mathematicaloperators (c) return 8704 <= c and c <= 8959 end
function block.miscellaneoustechnical (c) return 8960 <= c and c <= 9215 end
function block.controlpictures (c) return 9216 <= c and c <= 9279 end
function block.opticalcharacterrecognition (c) return 9280 <= c and c <= 9311 end
function block.enclosedalphanumerics (c) return 9312 <= c and c <= 9471 end
function block.boxdrawing (c) return 9472 <= c and c <= 9599 end
function block.blockelements (c) return 9600 <= c and c <= 9631 end
function block.geometricshapes (c) return 9632 <= c and c <= 9727 end
function block.miscellaneoussymbols (c) return 9728 <= c and c <= 9983 end
function block.dingbats (c) return 9984 <= c and c <= 10175 end
function block.miscellaneousmathematicalsymbolsa (c) return 10176 <= c and c <= 10223 end
function block.supplementalarrowsa (c) return 10224 <= c and c <= 10239 end
function block.braillepatterns (c) return 10240 <= c and c <= 10495 end
function block.supplementalarrowsb (c) return 10496 <= c and c <= 10623 end
function block.miscellaneousmathematicalsymbolsb (c) return 10624 <= c and c <= 10751 end
function block.supplementalmathematicaloperators (c) return 10752 <= c and c <= 11007 end
function block.miscellaneoussymbolsandarrows (c) return 11008 <= c and c <= 11263 end
function block.glagolitic (c) return 11264 <= c and c <= 11359 end
function block.latinextendedc (c) return 11360 <= c and c <= 11391 end
function block.coptic (c) return 11392 <= c and c <= 11519 end
function block.georgiansupplement (c) return 11520 <= c and c <= 11567 end
function block.tifinagh (c) return 11568 <= c and c <= 11647 end
function block.ethiopicextended (c) return 11648 <= c and c <= 11743 end
function block.cyrillicextendeda (c) return 11744 <= c and c <= 11775 end
function block.supplementalpunctuation (c) return 11776 <= c and c <= 11903 end
function block.cjkradicalssupplement (c) return 11904 <= c and c <= 12031 end
function block.kangxiradicals (c) return 12032 <= c and c <= 12255 end
function block.ideographicdescriptioncharacters (c) return 12272 <= c and c <= 12287 end
function block.cjksymbolsandpunctuation (c) return 12288 <= c and c <= 12351 end
function block.hiragana (c) return 12352 <= c and c <= 12447 end
function block.katakana (c) return 12448 <= c and c <= 12543 end
function block.bopomofo (c) return 12544 <= c and c <= 12591 end
function block.hangulcompatibilityjamo (c) return 12592 <= c and c <= 12687 end
function block.kanbun (c) return 12688 <= c and c <= 12703 end
function block.bopomofoextended (c) return 12704 <= c and c <= 12735 end
function block.cjkstrokes (c) return 12736 <= c and c <= 12783 end
function block.katakanaphoneticextensions (c) return 12784 <= c and c <= 12799 end
function block.enclosedcjklettersandmonths (c) return 12800 <= c and c <= 13055 end
function block.cjkcompatibility (c) return 13056 <= c and c <= 13311 end
function block.cjkunifiedideographsextensiona (c) return 13312 <= c and c <= 19903 end
function block.yijinghexagramsymbols (c) return 19904 <= c and c <= 19967 end
function block.cjkunifiedideographs (c) return 19968 <= c and c <= 40959 end
function block.yisyllables (c) return 40960 <= c and c <= 42127 end
function block.yiradicals (c) return 42128 <= c and c <= 42191 end
function block.lisu (c) return 42192 <= c and c <= 42239 end
function block.vai (c) return 42240 <= c and c <= 42559 end
function block.cyrillicextendedb (c) return 42560 <= c and c <= 42655 end
function block.bamum (c) return 42656 <= c and c <= 42751 end
function block.modifiertoneletters (c) return 42752 <= c and c <= 42783 end
function block.latinextendedd (c) return 42784 <= c and c <= 43007 end
function block.sylotinagri (c) return 43008 <= c and c <= 43055 end
function block.commonindicnumberforms (c) return 43056 <= c and c <= 43071 end
function block.phagspa (c) return 43072 <= c and c <= 43135 end
function block.saurashtra (c) return 43136 <= c and c <= 43231 end
function block.devanagariextended (c) return 43232 <= c and c <= 43263 end
function block.kayahli (c) return 43264 <= c and c <= 43311 end
function block.rejang (c) return 43312 <= c and c <= 43359 end
function block.hanguljamoextendeda (c) return 43360 <= c and c <= 43391 end
function block.javanese (c) return 43392 <= c and c <= 43487 end
function block.myanmarextendedb (c) return 43488 <= c and c <= 43519 end
function block.cham (c) return 43520 <= c and c <= 43615 end
function block.myanmarextendeda (c) return 43616 <= c and c <= 43647 end
function block.taiviet (c) return 43648 <= c and c <= 43743 end
function block.meeteimayekextensions (c) return 43744 <= c and c <= 43775 end
function block.ethiopicextendeda (c) return 43776 <= c and c <= 43823 end
function block.latinextendede (c) return 43824 <= c and c <= 43887 end
function block.cherokeesupplement (c) return 43888 <= c and c <= 43967 end
function block.meeteimayek (c) return 43968 <= c and c <= 44031 end
function block.hangulsyllables (c) return 44032 <= c and c <= 55215 end
function block.hanguljamoextendedb (c) return 55216 <= c and c <= 55295 end
function block.highsurrogates (c) return 55296 <= c and c <= 56191 end
function block.highprivateusesurrogates (c) return 56192 <= c and c <= 56319 end
function block.lowsurrogates (c) return 56320 <= c and c <= 57343 end
function block.privateusearea (c) return 57344 <= c and c <= 63743 end
function block.cjkcompatibilityideographs (c) return 63744 <= c and c <= 64255 end
function block.alphabeticpresentationforms (c) return 64256 <= c and c <= 64335 end
function block.arabicpresentationformsa (c) return 64336 <= c and c <= 65023 end
function block.variationselectors (c) return 65024 <= c and c <= 65039 end
function block.verticalforms (c) return 65040 <= c and c <= 65055 end
function block.combininghalfmarks (c) return 65056 <= c and c <= 65071 end
function block.cjkcompatibilityforms (c) return 65072 <= c and c <= 65103 end
function block.smallformvariants (c) return 65104 <= c and c <= 65135 end
function block.arabicpresentationformsb (c) return 65136 <= c and c <= 65279 end
function block.halfwidthandfullwidthforms (c) return 65280 <= c and c <= 65519 end
function block.specials (c) return 65520 <= c and c <= 65535 end
function block.linearbsyllabary (c) return 65536 <= c and c <= 65663 end
function block.linearbideograms (c) return 65664 <= c and c <= 65791 end
function block.aegeannumbers (c) return 65792 <= c and c <= 65855 end
function block.ancientgreeknumbers (c) return 65856 <= c and c <= 65935 end
function block.ancientsymbols (c) return 65936 <= c and c <= 65999 end
function block.phaistosdisc (c) return 66000 <= c and c <= 66047 end
function block.lycian (c) return 66176 <= c and c <= 66207 end
function block.carian (c) return 66208 <= c and c <= 66271 end
function block.copticepactnumbers (c) return 66272 <= c and c <= 66303 end
function block.olditalic (c) return 66304 <= c and c <= 66351 end
function block.gothic (c) return 66352 <= c and c <= 66383 end
function block.oldpermic (c) return 66384 <= c and c <= 66431 end
function block.ugaritic (c) return 66432 <= c and c <= 66463 end
function block.oldpersian (c) return 66464 <= c and c <= 66527 end
function block.deseret (c) return 66560 <= c and c <= 66639 end
function block.shavian (c) return 66640 <= c and c <= 66687 end
function block.osmanya (c) return 66688 <= c and c <= 66735 end
function block.osage (c) return 66736 <= c and c <= 66815 end
function block.elbasan (c) return 66816 <= c and c <= 66863 end
function block.caucasianalbanian (c) return 66864 <= c and c <= 66927 end
function block.lineara (c) return 67072 <= c and c <= 67455 end
function block.cypriotsyllabary (c) return 67584 <= c and c <= 67647 end
function block.imperialaramaic (c) return 67648 <= c and c <= 67679 end
function block.palmyrene (c) return 67680 <= c and c <= 67711 end
function block.nabataean (c) return 67712 <= c and c <= 67759 end
function block.hatran (c) return 67808 <= c and c <= 67839 end
function block.phoenician (c) return 67840 <= c and c <= 67871 end
function block.lydian (c) return 67872 <= c and c <= 67903 end
function block.meroitichieroglyphs (c) return 67968 <= c and c <= 67999 end
function block.meroiticcursive (c) return 68000 <= c and c <= 68095 end
function block.kharoshthi (c) return 68096 <= c and c <= 68191 end
function block.oldsoutharabian (c) return 68192 <= c and c <= 68223 end
function block.oldnortharabian (c) return 68224 <= c and c <= 68255 end
function block.manichaean (c) return 68288 <= c and c <= 68351 end
function block.avestan (c) return 68352 <= c and c <= 68415 end
function block.inscriptionalparthian (c) return 68416 <= c and c <= 68447 end
function block.inscriptionalpahlavi (c) return 68448 <= c and c <= 68479 end
function block.psalterpahlavi (c) return 68480 <= c and c <= 68527 end
function block.oldturkic (c) return 68608 <= c and c <= 68687 end
function block.oldhungarian (c) return 68736 <= c and c <= 68863 end
function block.ruminumeralsymbols (c) return 69216 <= c and c <= 69247 end
function block.brahmi (c) return 69632 <= c and c <= 69759 end
function block.kaithi (c) return 69760 <= c and c <= 69839 end
function block.sorasompeng (c) return 69840 <= c and c <= 69887 end
function block.chakma (c) return 69888 <= c and c <= 69967 end
function block.mahajani (c) return 69968 <= c and c <= 70015 end
function block.sharada (c) return 70016 <= c and c <= 70111 end
function block.sinhalaarchaicnumbers (c) return 70112 <= c and c <= 70143 end
function block.khojki (c) return 70144 <= c and c <= 70223 end
function block.multani (c) return 70272 <= c and c <= 70319 end
function block.khudawadi (c) return 70320 <= c and c <= 70399 end
function block.grantha (c) return 70400 <= c and c <= 70527 end
function block.newa (c) return 70656 <= c and c <= 70783 end
function block.tirhuta (c) return 70784 <= c and c <= 70879 end
function block.siddham (c) return 71040 <= c and c <= 71167 end
function block.modi (c) return 71168 <= c and c <= 71263 end
function block.mongoliansupplement (c) return 71264 <= c and c <= 71295 end
function block.takri (c) return 71296 <= c and c <= 71375 end
function block.ahom (c) return 71424 <= c and c <= 71487 end
function block.warangciti (c) return 71840 <= c and c <= 71935 end
function block.zanabazarsquare (c) return 72192 <= c and c <= 72271 end
function block.soyombo (c) return 72272 <= c and c <= 72367 end
function block.paucinhau (c) return 72384 <= c and c <= 72447 end
function block.bhaiksuki (c) return 72704 <= c and c <= 72815 end
function block.marchen (c) return 72816 <= c and c <= 72895 end
function block.masaramgondi (c) return 72960 <= c and c <= 73055 end
function block.cuneiform (c) return 73728 <= c and c <= 74751 end
function block.cuneiformnumbersandpunctuation (c) return 74752 <= c and c <= 74879 end
function block.earlydynasticcuneiform (c) return 74880 <= c and c <= 75087 end
function block.egyptianhieroglyphs (c) return 77824 <= c and c <= 78895 end
function block.anatolianhieroglyphs (c) return 82944 <= c and c <= 83583 end
function block.bamumsupplement (c) return 92160 <= c and c <= 92735 end
function block.mro (c) return 92736 <= c and c <= 92783 end
function block.bassavah (c) return 92880 <= c and c <= 92927 end
function block.pahawhhmong (c) return 92928 <= c and c <= 93071 end
function block.miao (c) return 93952 <= c and c <= 94111 end
function block.ideographicsymbolsandpunctuation (c) return 94176 <= c and c <= 94207 end
function block.tangut (c) return 94208 <= c and c <= 100351 end
function block.tangutcomponents (c) return 100352 <= c and c <= 101119 end
function block.kanasupplement (c) return 110592 <= c and c <= 110847 end
function block.kanaextendeda (c) return 110848 <= c and c <= 110895 end
function block.nushu (c) return 110960 <= c and c <= 111359 end
function block.duployan (c) return 113664 <= c and c <= 113823 end
function block.shorthandformatcontrols (c) return 113824 <= c and c <= 113839 end
function block.byzantinemusicalsymbols (c) return 118784 <= c and c <= 119039 end
function block.musicalsymbols (c) return 119040 <= c and c <= 119295 end
function block.ancientgreekmusicalnotation (c) return 119296 <= c and c <= 119375 end
function block.taixuanjingsymbols (c) return 119552 <= c and c <= 119647 end
function block.countingrodnumerals (c) return 119648 <= c and c <= 119679 end
function block.mathematicalalphanumericsymbols (c) return 119808 <= c and c <= 120831 end
function block.suttonsignwriting (c) return 120832 <= c and c <= 121519 end
function block.glagoliticsupplement (c) return 122880 <= c and c <= 122927 end
function block.mendekikakui (c) return 124928 <= c and c <= 125151 end
function block.adlam (c) return 125184 <= c and c <= 125279 end
function block.arabicmathematicalalphabeticsymbols (c) return 126464 <= c and c <= 126719 end
function block.mahjongtiles (c) return 126976 <= c and c <= 127023 end
function block.dominotiles (c) return 127024 <= c and c <= 127135 end
function block.playingcards (c) return 127136 <= c and c <= 127231 end
function block.enclosedalphanumericsupplement (c) return 127232 <= c and c <= 127487 end
function block.enclosedideographicsupplement (c) return 127488 <= c and c <= 127743 end
function block.miscellaneoussymbolsandpictographs (c) return 127744 <= c and c <= 128511 end
function block.emoticons (c) return 128512 <= c and c <= 128591 end
function block.ornamentaldingbats (c) return 128592 <= c and c <= 128639 end
function block.transportandmapsymbols (c) return 128640 <= c and c <= 128767 end
function block.alchemicalsymbols (c) return 128768 <= c and c <= 128895 end
function block.geometricshapesextended (c) return 128896 <= c and c <= 129023 end
function block.supplementalarrowsc (c) return 129024 <= c and c <= 129279 end
function block.supplementalsymbolsandpictographs (c) return 129280 <= c and c <= 129535 end
function block.cjkunifiedideographsextensionb (c) return 131072 <= c and c <= 173791 end
function block.cjkunifiedideographsextensionc (c) return 173824 <= c and c <= 177983 end
function block.cjkunifiedideographsextensiond (c) return 177984 <= c and c <= 178207 end
function block.cjkunifiedideographsextensione (c) return 178208 <= c and c <= 183983 end
function block.cjkunifiedideographsextensionf (c) return 183984 <= c and c <= 191471 end
function block.cjkcompatibilityideographssupplement (c) return 194560 <= c and c <= 195103 end
function block.tags (c) return 917504 <= c and c <= 917631 end
function block.variationselectorssupplement (c) return 917760 <= c and c <= 917999 end
function block.supplementaryprivateuseareaa (c) return 983040 <= c and c <= 1048575 end
function block.supplementaryprivateuseareab (c) return 1048576 <= c and c <= 1114111 end

category = {}
function category.Lm (c)
   return false end
function category.Zs (c)
   if c == 32 then return true end
   return false end
function category.Nd (c)
   if 48 <= c and c <= 57 then return true end
   return false end
function category.Co (c)
   return false end
function category.Mc (c)
   return false end
function category.Pc (c)
   if c == 95 then return true end
   return false end
function category.No (c)
   return false end
function category.Pi (c)
   return false end
function category.Lo (c)
   return false end
function category.So (c)
   return false end
function category.Cs (c)
   return false end
function category.Sk (c)
   if c == 94 then return true end
   if c == 96 then return true end
   return false end
function category.Pd (c)
   if c == 45 then return true end
   return false end
function category.Sc (c)
   if c == 36 then return true end
   return false end
function category.Mn (c)
   return false end
function category.Po (c)
   if 33 <= c and c <= 35 then return true end
   if 37 <= c and c <= 39 then return true end
   if c == 42 then return true end
   if c == 44 then return true end
   if 46 <= c and c <= 47 then return true end
   if 58 <= c and c <= 59 then return true end
   if 63 <= c and c <= 64 then return true end
   if c == 92 then return true end
   return false end
function category.Cn (c)
   return false end
function category.Pe (c)
   if c == 41 then return true end
   if c == 93 then return true end
   if c == 125 then return true end
   return false end
function category.Cf (c)
   return false end
function category.Me (c)
   return false end
function category.Lt (c)
   return false end
function category.Zp (c)
   return false end
function category.Cc (c)
   if 0 <= c and c <= 31 then return true end
   return false end
function category.Pf (c)
   return false end
function category.Lu (c)
   if 65 <= c and c <= 90 then return true end
   return false end
function category.Ps (c)
   if c == 40 then return true end
   if c == 91 then return true end
   if c == 123 then return true end
   return false end
function category.Ll (c)
   if 97 <= c and c <= 122 then return true end
   return false end
function category.Sm (c)
   if c == 43 then return true end
   if 60 <= c and c <= 62 then return true end
   if c == 124 then return true end
   if c == 126 then return true end
   return false end
function category.Nl (c)
   return false end
function category.Zl (c)
   return false end
function category.M (c)
   return category.Mc(c) or category.Mn(c) or category.Me(c) end
function category.S (c)
   return category.So(c) or category.Sk(c) or category.Sc(c) or category.Sm(c) end
function category.N (c)
   return category.Nd(c) or category.No(c) or category.Nl(c) end
function category.Z (c)
   return category.Zs(c) or category.Zp(c) or category.Zl(c) end
function category.L (c)
   return category.Lm(c) or category.Lo(c) or category.Lt(c) or category.Lu(c) or category.Ll(c) end
function category.C (c)
   return category.Co(c) or category.Cs(c) or category.Cn(c) or category.Cf(c) or category.Cc(c) end
function category.P (c)
   return category.Pc(c) or category.Pi(c) or category.Pd(c) or category.Po(c) or category.Pe(c) or category.Pf(c) or category.Ps(c) end
