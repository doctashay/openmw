function (get_whole_archive_options OUT_VAR)
    # We use --whole-archive because OSG plugins use registration.
    # macOS 10.5 Leopard's linker doesn't support --whole-archive, so use -force_load
    if (APPLE)
        # Check if building for macOS 10.5
        if (OPENMW_MACOSX_10_5 OR (CMAKE_OSX_DEPLOYMENT_TARGET AND CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS "10.6"))
            # macOS 10.5 uses its own linker, use -force_load for specific library
            # -force_load requires the library path immediately after it (with comma syntax)
            foreach(_lib ${ARGN})
                list(APPEND ${OUT_VAR} -Wl,-force_load,${_lib})
            endforeach()
            set(${OUT_VAR} ${${OUT_VAR}} PARENT_SCOPE)
        elseif (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" OR CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
            # Modern linkers (macOS 10.6+) support --whole-archive
            set(${OUT_VAR} -Wl,--whole-archive ${ARGN} -Wl,--no-whole-archive PARENT_SCOPE)
        else ()
            message(FATAL_ERROR "get_whole_archive_options not implemented for CMAKE_CXX_COMPILER_ID ${CMAKE_CXX_COMPILER_ID}")
        endif()
    elseif (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" OR CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
        # Non-macOS: use --whole-archive
        set(${OUT_VAR} -Wl,--whole-archive ${ARGN} -Wl,--no-whole-archive PARENT_SCOPE)
    else ()
        message(FATAL_ERROR "get_whole_archive_options not implemented for CMAKE_CXX_COMPILER_ID ${CMAKE_CXX_COMPILER_ID}")
    endif()
endfunction ()
