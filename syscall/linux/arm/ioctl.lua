-- ARM ioctl differences

local function init(s)

local arch = {
  ioctl = {
    FIOQSIZE = 0x545E,
  }
}

return arch

end

return {init = init}

