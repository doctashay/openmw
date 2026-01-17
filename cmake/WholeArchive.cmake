function (get_whole_archive_options OUT_VAR)
    # We use --whole-archive because OSG plugins use registration.
    # On macOS, even with GCC, we must use macOS linker flags (-all_load)
    if (APPLE)
        # macOS uses its own linker, so use -all_load even with GCC
        set(${OUT_VAR} -Wl,-all_load ${ARGN} -Wl,-noall_load PARENT_SCOPE)
    elseif (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" OR CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        # Linux/other platforms with GNU ld or Clang
        set(${OUT_VAR} -Wl,--whole-archive ${ARGN} -Wl,--no-whole-archive PARENT_SCOPE)
    else ()
        message(FATAL_ERROR "get_whole_archive_options not implemented for CMAKE_CXX_COMPILER_ID ${CMAKE_CXX_COMPILER_ID}")
    endif()
endfunction ()
