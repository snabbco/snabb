-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

local ok, err = pcall(require, "core.main")
if not ok then
   print("startup: unhandled exception")
   print(err)
   os.exit(1)
end
