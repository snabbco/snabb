-- types for rump kernel
-- only called when not on NetBSD so needs types fixing up

local function init(abi, c, errors, ostypes)

local unchanged = {
  char = true,
  int = true,
  long = true,
  unsigned = true,
  ["unsigned char"] = true,
  ["unsigned int"] = true,
  ["unsigned long"] = true,
  int8_t = true,
  int16_t = true,
  int32_t = true,
  int64_t = true,
  intptr_t = true,
  uint8_t = true,
  uint16_t = true,
  uint32_t = true,
  uint64_t = true,
  uintptr_t = true,
-- same in all OSs at present
  in_port_t = true,
  uid_t = true,
  gid_t = true,
  id_t = true,
  pid_t = true,
  off_t = true,
  nfds_t = true,
  size_t = true,
  ssize_t = true,
  socklen_t = true,
  ["struct in_addr"] = true,
  ["struct in6_addr"] = true,
  ["struct iovec"] = true,
}

local function rumpfn(tp) -- add _netbsd_ to correct types
  if unchanged[tp] then return tp end
  if tp == "void (*)(int, siginfo_t *, void *)" then return "void (*)(int, _netbsd_siginfo_t *, void *)" end
  if string.find(tp, "struct") then
    return string.gsub(tp, "struct (%a)", "struct _netbsd_%1")
  end
  return "_netbsd_" .. tp
end

return require "syscall.types".init(abi, c, errors, ostypes, rumpfn)

end

return {init = init}


