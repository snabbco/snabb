module(..., package.seeall)

local link = require("core.link")

Fwd = {}

function Fwd:new()
  return setmetatable({transmitted = 0}, {__index = Fwd})
end

function Fwd:pull()
  assert(self.output.output, "Fwd: output link not created")
  assert(self.input.input, "Fwd: input link not created")
  local n = link.nreadable(self.input.input)
  for _ = 1, n do
    link.transmit(self.output.output, link.receive(self.input.input))
  end
  self.transmitted = self.transmitted + n
end

function Fwd:report()
  print(string.format("Fwd '%s' transmitted %d packets",
    self.appname, self.transmitted))
end
