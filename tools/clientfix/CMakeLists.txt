cmake_minimum_required(VERSION 3.20)
project(HordesOfAzerothClientFix CXX)

if (NOT CMAKE_SIZEOF_VOID_P EQUAL 4)
    message(FATAL_ERROR "Build 32-bit (-A Win32): the 1.12.1 client is a 32-bit program.")
endif()

add_library(HordesOfAzerothClientFix SHARED HordesOfAzerothClientFix.cpp Controller.cpp Interact.cpp Borderless.cpp Coop.cpp LoginRecovery.cpp)
set_target_properties(HordesOfAzerothClientFix PROPERTIES
    CXX_STANDARD 17
    MSVC_RUNTIME_LIBRARY "MultiThreaded")
target_compile_options(HordesOfAzerothClientFix PRIVATE /W4)
target_link_libraries(HordesOfAzerothClientFix PRIVATE setupapi hid)
