module(..., package.seeall)

local link = require("core.link")

Echo = {}

function Echo:new()
  return setmetatable({transmitted = 0}, {__index = Echo})
end

function Echo:pull()
  assert(self.output.output, "Echo: output link not created")
  assert(self.input.input, "Echo: input link not created")
  local n = link.nreadable(self.input.input)
  for _ = 1, n do
    link.transmit(self.output.output, link.receive(self.input.input))
  end
  self.transmitted = self.transmitted + n
end

function Echo:report()
  print(string.format("Echo '%s' transmitted %d packets",
    self.appname, self.transmitted))
end
