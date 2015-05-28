local ok, err = pcall(require, "core.main")
if not ok then
   print("startup: unhandled exception")
   print(err)
   os.exit(1)
end
