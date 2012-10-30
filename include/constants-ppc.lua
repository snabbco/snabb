-- ppc specific code

error("ppc support is coming soon")

local arch = {}

arch.socketoptions = function(c)
  error("ppc socketoptions need to be set")
end

return arch

