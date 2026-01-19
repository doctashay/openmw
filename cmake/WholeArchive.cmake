function (get_whole_archive_options OUT_VAR)
    # We use --whole-archive because OSG plugins use registration.
    # macOS 10.5 Leopard's linker doesn't support --whole-archive, so use -all_load
    if (APPLE AND OPENMW_MACOSX_10_5)
        # macOS 10.5 uses its own linker, so use -all_load even with GCC/Clang
        set(${OUT_VAR} -Wl,-all_load ${ARGN} -Wl,-noall_load PARENT_SCOPE)
    elseif (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" OR CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
        # Modern linkers (including macOS 10.6+) support --whole-archive
        set(${OUT_VAR} -Wl,--whole-archive ${ARGN} -Wl,--no-whole-archive PARENT_SCOPE)
    else ()
        message(FATAL_ERROR "get_whole_archive_options not implemented for CMAKE_CXX_COMPILER_ID ${CMAKE_CXX_COMPILER_ID}")
    endif()
endfunction ()
