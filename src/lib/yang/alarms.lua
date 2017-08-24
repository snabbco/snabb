module(..., package.seeall)

function raise_alarm (key, args)
   print('raise_alarm')
   assert(type(key) == 'table')
   assert(type(args) == 'table')
end

function clear_alarm (key)
   print('clear alarm')
   assert(type(key) == 'table')
end
