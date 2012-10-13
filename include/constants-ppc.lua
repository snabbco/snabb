-- ppc specific code

error("ppc support is coming soon")

local arch = {}

arch.socketoptions = function(S)
  error("ppc socketoptions need to be set")
end

return arch

