include_directories(
    ${CMAKE_SOURCE_DIR}/lib/luajit/usr/local/include/luajit-2.1
    )

#	$(Q) $(CC) $(DEBUG) -Wl,--no-as-needed -Wl,-E -Werror -Wall -o $@ $^ \
# 	    ../lib/luajit/src/libluajit.a \
#
set(CMAKE_C_FLAGS "-Wl,--no-as-needed -Wl,-E -Werror -Wall ${CMAKE_C_FLAGS}")

set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -L${CMAKE_SOURCE_DIR}/lib/luajit/usr/local/lib -lrt -lc -ldl -lm -lpthread -lluajit-5.1")

add_executable (snabb core/snabbswitch.c)

# Link the executable to the Hello library. Since the Hello library has
# public include directories we will use those link directories when building
# helloDemo

add_dependencies(snabb luajit copy_ljsyscall)

# target_link_libraries (snabb LINK_PUBLIC luajit)