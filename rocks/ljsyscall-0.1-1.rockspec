package = "ljsyscall"
version = "0.1-1"
source = {
	url = "https://download.github.com/justincormack-ljsyscall-v0.1-0-gc6a669f.tar.gz",
	md5 = "01301be26ffc8f44ff28121702e36e58"
    dir = "justincormack-ljsyscall-a916375"
}
description = {
	summary = "Linux system calls for LuaJIT",
	detailed = [[
		An FFI implementation of the Linux system calls for LuaJIT.
	]],
	homepage = "https://github.com/justincormack/ljsyscall",
	maintainer = "Justin Cormack <justin@specialbusservice.com>",
	license = "MIT/X11"
}
dependencies = {
	"lua >= 5.1",
}
build = {
	type = "builtin",
	modules = {
		syscall = "syscall.lua",
	}
}

