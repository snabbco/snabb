local macaddress = require "lib.macaddress"

return {
   basic_handling = function ()
      local macA = macaddress:new('00-01-02-0a-0b-0c')
      local macB = macaddress:new('0001020A0B0C')
      local macC = macaddress:new('0A:0B:0C:00:01:02')
      assert (tostring(macA) == '00:01:02:0A:0B:0C', "bad canonical MAC")
      assert (macA == macB, "macA and macB should be equal")
      assert (macA ~= macC, "macA and macC should be different")
      assert (macA:subbits(0,31)==0x0a020100, "low A")
      assert (macA:subbits(32,48)==0x0c0b, ("hi A (%X)"):format(macA:subbits(32,48)))
      assert (macC:subbits(0,31)==0x000c0b0a, "low C")
      assert (macC:subbits(32,48)==0x0201," hi C")
   end,
}
