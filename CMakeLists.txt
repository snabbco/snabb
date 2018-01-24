cmake_minimum_required (VERSION 2.8.11)
project (snabb)

set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

set(MAKE make)
set(LUAJIT_CFLAGS ${CMAKE_SOURCE_DIR}/gcc-preinclude.h)

add_custom_target(
   luajit
   COMMAND $(MAKE) PREFIX=`pwd`/usr/local CFLAGS="$(LUAJIT_CFLAGS)" && $(MAKE) DESTDIR=`pwd` install
   WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/lib/luajit
)

ADD_CUSTOM_TARGET(
    make_ln_luajit
    echo "make a ln -s to luajit"
    COMMAND ln -fs luajit-2.1.0-beta1 luajit
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/lib/luajit/usr/local/bin
    DEPENDS luajit)

# copy file
file(MAKE_DIRECTORY ${CMAKE_SOURCE_DIR}/src/syscall/linux)

add_custom_target(copy_ljsyscall)

add_custom_command(TARGET copy_ljsyscall PRE_BUILD
                   COMMAND ${CMAKE_COMMAND} -E
                   copy ${CMAKE_SOURCE_DIR}/lib/ljsyscall/syscall.lua   ${CMAKE_SOURCE_DIR}/src/ )
add_custom_command(TARGET copy_ljsyscall PRE_BUILD
                   COMMAND ${CMAKE_COMMAND} -E
                   copy ${CMAKE_SOURCE_DIR}/lib/ljsyscall/syscall/*.lua   ${CMAKE_SOURCE_DIR}/src/syscall/ )
add_custom_command(TARGET copy_ljsyscall PRE_BUILD
                   COMMAND ${CMAKE_COMMAND} -E
                   copy ${CMAKE_SOURCE_DIR}/lib/ljsyscall/syscall/linux/*.lua   ${CMAKE_SOURCE_DIR}/src/syscall/linux/ )
add_custom_command(TARGET copy_ljsyscall PRE_BUILD
                   COMMAND ${CMAKE_COMMAND} -E
                   copy ${CMAKE_SOURCE_DIR}/lib/ljsyscall/syscall/linux/x64/*.lua   ${CMAKE_SOURCE_DIR}/src/syscall/linux/ )
add_custom_command(TARGET copy_ljsyscall PRE_BUILD
                   COMMAND ${CMAKE_COMMAND} -E
                   copy ${CMAKE_SOURCE_DIR}/lib/ljsyscall/syscall/shared/*.lua   ${CMAKE_SOURCE_DIR}/src/syscall/ )

# do copy file task here
add_subdirectory (src)
