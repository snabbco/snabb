set(CMAKE_LUA_OUTPUT_EXTENSION ".o")
set(CMAKE_LUA_OUTPUT_EXTENSION_REPLACE 1)

set(CMAKE_LUA_FLAGS " -bg")
set(CMAKE_LUA_COMPILER ${CMAKE_SOURCE_DIR}/lib/luajit/usr/local/bin/luajit CACHE FILEPATH "The LuaJIT compiler")

set(CMAKE_LUA_COMPILE_OBJECT  "<CMAKE_LUA_COMPILER> <FLAGS> <SOURCE> <OBJECT>")
set(CMAKE_LUA_SOURCE_FILE_EXTENSIONS lua;luah)

# message("CMAKE_LUA_COMPILE_OBJECT is ${CMAKE_LUA_COMPILE_OBJECT}")


enable_language(LUA OPTIONAL)

include_directories(
    ${CMAKE_SOURCE_DIR}/lib/luajit/src/
    ${CMAKE_SOURCE_DIR}/src/
    )

#	$(Q) $(CC) $(DEBUG) -Wl,--no-as-needed -Wl,-E -Werror -Wall -o $@ $^ \
# 	    ../lib/luajit/src/libluajit.a \
#
set(CMAKE_C_FLAGS "-Wl,--no-as-needed -Wl,-E -Werror -Wall ${CMAKE_C_FLAGS}")

set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -lrt -lc -ldl -lm -lpthread ")

# Lua C FFI Header

set(LUA_HEADERS
    core/lib.h
    core/link.h
    core/clib.h
    lib/ipc/shmem/shmem.h
    )

set(LUA_LUA_HEADERS_SRCS )

file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/src/core)
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/src/lib/io)
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/src/lib/ipc)
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/src/lib/ipc/shmem)

foreach(lua_head ${LUA_HEADERS})
    ADD_CUSTOM_COMMAND(
        OUTPUT ${CMAKE_BINARY_DIR}/src/${lua_head}.luah
        COMMAND echo 'module\(...,package.seeall\); require\(\"ffi\"\).cdef[=============[' > '${CMAKE_BINARY_DIR}/src/${lua_head}.luah'
        COMMAND cat ${CMAKE_SOURCE_DIR}/src/${lua_head} >> ${CMAKE_BINARY_DIR}/src/${lua_head}.luah
        COMMAND echo ']=============]'>>${CMAKE_BINARY_DIR}/src/${lua_head}.luah
        DEPENDS ${CMAKE_SOURCE_DIR}/src/${lua_head}
    )
    list(APPEND LUA_LUA_HEADERS_SRCS ${CMAKE_BINARY_DIR}/src/${lua_head}.luah)

    # update
    STRING(REPLACE "." "_" lua_source_module_name ${lua_head})
    STRING(REPLACE "/" "." lua_source_module_name ${lua_source_module_name})
    STRING(REGEX REPLACE "\\.luah$" "" lua_source_module_name ${lua_source_module_name})
    set_source_files_properties(${CMAKE_BINARY_DIR}/src/${lua_head}.luah
                                PROPERTIES COMPILE_FLAGS "-n ${lua_source_module_name}")
endforeach()

message(${LUA_LUA_HEADERS_SRCS})

# Lua Module
set(LUA_SRCS
    core/startup.lua
    core/main.lua
    core/shm.lua
    lib/ipc/shmem/shmem.lua
    )

foreach(lua_source ${LUA_SRCS})
    STRING(REPLACE "/" "." lua_source_module_name ${lua_source})
    STRING(REGEX REPLACE "\\.lua$" "" lua_source_module_name ${lua_source_module_name})
    # MESSAGE( STATUS "Including dir " ${lua_source} ${lua_source_module_name} )
    set_source_files_properties(${lua_source}
                                PROPERTIES COMPILE_FLAGS "-n ${lua_source_module_name}")
endforeach()

# C code
set(C_SRCS
    arch/avx2.c
    arch/sse2.c
    core/lib.c
    core/memory.c
    lib/checksum.c
    lib/ipc/shmem/shmem.c
    )

set_source_files_properties(arch/avx2.c
                                PROPERTIES COMPILE_FLAGS " -O2 -mavx2 ")
set_source_files_properties(arch/sse2.c
                                PROPERTIES COMPILE_FLAGS " -O2 -msse2 ")

add_executable (snabb core/snabbswitch.c ${C_SRCS} ${LUA_LUA_HEADERS_SRCS} ${LUA_SRCS})

# Link the executable to the Hello library. Since the Hello library has
# public include directories we will use those link directories when building
# helloDemo

add_dependencies(snabb luajit copy_ljsyscall)
target_link_libraries(snabb ${CMAKE_SOURCE_DIR}/lib/luajit/src/libluajit.a)

# target_link_libraries (snabb LINK_PUBLIC luajit)