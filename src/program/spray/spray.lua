-- spray: program to replay a trace and add packet loss

local snabb = require("snabb1") -- Use API version 1

-- Check command line
if #arg ~= 2 then
   print(require("program.spray.README_inc"))
   os.exit(0)
end

local inputfile, outputfile = unpack(arg)

-- Setup
local conf = snabb.config()
conf:config_set_app('reader', 'pcap_reader', inputfile)
conf:config_set_app('sprayer', 'sprayer')
conf:config_set_app('writer',  'pcap_writer', outputfile)
conf:config_set_link('reader.output -> sprayer.input')
conf:config_set_link('sprayer.output -> writer.input')

-- Execute
local engine = snabb.engine()
engine:engine_configure(config)
print(("Spraying packets from %s to %s"):format(inputfile, outputfile))
engine:engine_run({duration = 'toidle'})

-- Report
print(("Processed %d packets"):format(engine:engine_processed_packets()))

