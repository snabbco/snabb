--- Abstract multiqueue API
--- this module creates an easier to use layer for multiqueue-capable hardware
--- the underlying driver presents a fork-style API, this one allows the user
--- to simply instantiate several device handles on the same pci address


module(...,package.seeall)

local _devices = {}

function new(drv, devaddr)
   local dev = _devices[devaddr]
   if not dev then
      _devices[devaddr] = {
         pf = drv:new(devaddr),
         vflist = {n=0},
      }
      dev = _devices[devaddr]
   end
   local vf = dev.pf:new_pool(dev.vflist.n)
   dev.vflist[dev.vflist.n] = vf
   dev.vflist.n = dev.vflist.n+1
   return vf, dev.pf
end


--- test code ---

local function mock_drv(name)
   local function mth(n)
      return function (self, ...)
         self._rec[#self._rec+1] = {n, ...}
         return mock_drv(name..'.'..n)
      end
   end
   return {
      _name = name,
      _rec = {},
      _dump = function (t)
         print (t._name..':')
         for _,v in ipairs(t._rec) do
            print (table.concat(v, ','))
         end
      end,
      _test = function(self, t)
         assert(#t == #self._rec,
            ("%d calls, %d expected"):format(#self._rec, #t))
         for i=1, #t do
            local nm = table.concat(self._rec[i], ',')
            assert(t[i] == nm,
               ("call #%d: found %q, expected %q"):format(i, nm, t[i]))
         end
      end,
      new = mth('new'),
      new_pool = mth('new_pool'),
   }
end

function selftest()
   mockdev = mock_drv('drv')
   local d1q1,dA = assert(new(mockdev, 'PCI[001]'))
   local d1q2,dB = assert(new(mockdev, 'PCI[001]'))
   local d2q1,dC = assert(new(mockdev, 'PCI[002]'))
   assert (dA == dB, 'first two should be the same device')
   assert (dA ~= dC, 'the third is a different device')
   mockdev:_test{'new,PCI[001]', 'new,PCI[002]'}
   dA:_test{'new_pool,0', 'new_pool,1'}
   d1q1:_test{}
   d1q2:_test{}
   dC:_test{'new_pool,0'}
   d2q1:_test{}
   print ('ok')
end
