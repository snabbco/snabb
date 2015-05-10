-- spray: program to replay a trace and add packet loss

local snabb = require("snabb1") -- Use API version 1

-- Check command line
if #arg ~= 2 then
   print(require("program.spray.README_inc"))
   os.exit(0)
end

local inputfile, outputfile = unpack(arg)

-- Setup
local config = snabb.config()
config:set_app('reader', 'pcap_reader', inputfile)
config:set_app('sprayer', 'sprayer')
config:set_app('writer',  'pcap_writer', outputfile)
config:set_link('reader.output -> sprayer.input')
config:set_link('sprayer.output -> writer.input')

-- Execute
local engine = snabb.engine()
engine:configure(config)
print(("Spraying packets from %s to %s"):format(inputfile, outputfile))
engine:run({duration = 'toidle'})

-- Report
print(("Processed %d packets"):format(engine:packet()))

