-- ARM ioctl differences

return function(s)

local arch = {
  ioctl = {
    FIOQSIZE = 0x545E,
  }
}

return arch

end

