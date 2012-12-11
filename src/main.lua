module(...,package.seeall)

function main ()
   require "selftest"
end

function handler (reason)
   print(reason)
   -- print(debug.traceback())
   -- debug.debug()
   os.exit(1)
end

xpcall(main, handler)

