------------------------------------------------------------------------------
-- DynASM x64 module.
--
-- Copyright (C) 2005-2015 Mike Pall. All rights reserved.
-- See dynasm.lua for full copyright notice.
------------------------------------------------------------------------------
-- This module just sets 64 bit mode for the combined x86/x64 module.
-- All the interesting stuff is there.
------------------------------------------------------------------------------

--unload dasm_x86 if it's already loaded.
local dasm_x86 = package.loaded.dasm_x86
package.loaded.dasm_x86 = nil

rawset(_G, 'x64', true) -- Using a global is an ugly, but effective solution.
local dasm_x64 = require("dasm_x86")

package.loaded.dasm_x86 = dasm_x86 --put it back

return dasm_x64

