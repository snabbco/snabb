include(${CMAKE_ROOT}/Modules/CMakeDetermineCompiler.cmake)


set(CMAKE_LUA_COMPILER ${CMAKE_SOURCE_DIR}/lib/luajit/usr/local/bin/luajit CACHE FILEPATH "The LuaJIT compiler")
set(CMAKE_LUA_COMPILER_ENV_VAR "")

mark_as_advanced(CMAKE_LUA_COMPILER)

# configure variables set in this file for fast reload later on
configure_file(${CMAKE_SOURCE_DIR}/cmake/CMakeLUACompiler.cmake.in
  ${CMAKE_PLATFORM_INFO_DIR}/CMakeLUACompiler.cmake @ONLY)