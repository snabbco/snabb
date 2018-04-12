module(..., package.seeall)

local fwd = require("apps.fwd.fwd")
local intel = require("apps.intel.intel_app")
local numa = require("lib.numa")

function run(parameters)
  print("running echo")

  if #parameters > 4 or #parameters < 1 then
    print("Usage: echo <pci-addr> [chain-length] [duration] [cpu]\nexiting...")
    main.exit(1)
  end

  local pciaddr = parameters[1]
  local chainlen = tonumber(parameters[2]) or 1
  local cpu = tonumber(parameters[4])

  if chainlen < 1 then
    print("chain-length < 1, defaulting to 1")
    chainlen = 1
  end

  local c = config.new()

  config.app(c, "intel", intel.Intel82599, {pciaddr = pciaddr})

  for i = 1, chainlen do
    config.app(c, "fwd" .. i, fwd.Fwd)
  end

  for i = 1, chainlen - 1 do
    config.link(c, string.format("fwd%d.output -> fwd%d.input", i, i + 1))
  end

  config.link(c, "intel.tx -> fwd1.input")
  config.link(c, string.format("fwd%d.output -> intel.rx", chainlen))

  if cpu then numa.bind_to_cpu(cpu) end
  engine.configure(c)
  engine.busywait = true
  engine.main{duration = tonumber(parameters[3])}
end
