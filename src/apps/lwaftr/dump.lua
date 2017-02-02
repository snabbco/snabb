module(..., package.seeall)

local yang = require("lib.yang.yang")

local CONF_FILE_DUMP = "/tmp/lwaftr-%d.conf"

function dump_configuration(lwstate)
   local dest = (CONF_FILE_DUMP):format(os.time())
   print(("Dump lwAFTR configuration: '%s'"):format(dest))
   yang.print_data_for_schema_by_name('snabb-softwire-v2', lwstate.conf,
                                      io.open(dest, 'w'))
end

function selftest ()
   print("selftest: dump")
   print("ok")
end
