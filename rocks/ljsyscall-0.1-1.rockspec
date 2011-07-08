package = "ljsyscall"
version = "0.1-1"
source = {
	url = "https://github.com/justincormack/ljsyscall/tarball/",
	--md5 = ""
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

