export LUA_PATH="?;./?.lua"
export LUA_INIT="package.path = '?;'..package.path"

luajit -joff -e"_port=1" all.lua
if [ $? != 0 ] 
then
  echo "all.lua tests failed with JIT off"
  exit 1
fi


luajit -jon -e"_port=1" all.lua
if [ $? != 0 ] 
then
  echo "all.lua tests failed with JIT on"
  exit 1
fi

