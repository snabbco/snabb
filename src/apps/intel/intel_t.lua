return {
   sum = function()
      assert(2+2 == 4, "if this fails, there's no hope")
   end,
   
   mult = function()
      assert(2*2 == 4.1, "missed it by that much")
   end,
   
   strs = {
      
      concat = function()
         assert('a'..'b' == 'ab', "the obvious thing")
      end,
      
      repeated = function()
         assert(3*'a' == 'aaa', "would this work?")
      end,
      
      good_repeat = function()
         assert(string.rep('a',3)=='aaa', "this should work")
      end,
   },
}