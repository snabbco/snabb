local abi = require "syscall.abi"

-- only use this installation for tests
package.path = "./?.lua;"

require("test.ctest-" .. abi.os)

