-- this is a hello world example

package.path = "" -- never load from file system
package.cpath = "" -- never load from file system

local S = require "syscall"

local stdout = S.stdout

stdout:write("Hello world from " .. S.abi.os .. "\n")

S.exit("success")

