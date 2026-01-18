set(BSATOOL
    bsatool.cpp
)
source_group(apps\\bsatool FILES ${BSATOOL})

# Main executable
openmw_add_executable(bsatool
    ${BSATOOL}
)

target_link_libraries(bsatool
    Boost::program_options
    components
)

# PowerPC needs libatomic for atomic operations
if(OPENMW_ATOMIC_LIB)
    target_link_libraries(bsatool ${OPENMW_ATOMIC_LIB})
endif()

# PowerPC alignment workaround for Boost program_options
# The malloc_alignment_fix.cpp in components should handle this,
# but we ensure it's linked early by linking components first
if(APPLE AND (CMAKE_OSX_ARCHITECTURES MATCHES "ppc" OR OPENMW_POWERPC_BUILD))
    message(STATUS "bsatool: PowerPC build detected - using malloc alignment fix from components")
    # Ensure our malloc wrapper takes precedence by using linker flags
    # This makes our malloc/free override Boost's calls
    set_target_properties(bsatool PROPERTIES
        LINK_FLAGS "-Wl,-flat_namespace"
    )
endif()

# On macOS, add Boost library directory to rpath so executable can find dylibs at runtime
if(APPLE)
    set(BOOST_RPATH_DIRS "")
    
    # Get the actual library path from the Boost target
    if(TARGET Boost::program_options)
        get_target_property(BOOST_PO_LOCATION Boost::program_options IMPORTED_LOCATION)
        if(BOOST_PO_LOCATION)
            get_filename_component(BOOST_LIB_DIR "${BOOST_PO_LOCATION}" DIRECTORY)
            list(APPEND BOOST_RPATH_DIRS "${BOOST_LIB_DIR}")
            message(STATUS "bsatool: Found Boost library at: ${BOOST_PO_LOCATION}")
            message(STATUS "bsatool: Boost library directory: ${BOOST_LIB_DIR}")
        endif()
    endif()
    
    # Also add Boost_LIBRARY_DIRS if available
    if(Boost_LIBRARY_DIRS)
        list(APPEND BOOST_RPATH_DIRS "${Boost_LIBRARY_DIRS}")
    endif()
    
    # Add Boost_ROOT/lib if Boost_ROOT is set
    if(Boost_ROOT AND EXISTS "${Boost_ROOT}/lib")
        list(APPEND BOOST_RPATH_DIRS "${Boost_ROOT}/lib")
    endif()
    
    # Remove duplicates and set rpath
    if(BOOST_RPATH_DIRS)
        list(REMOVE_DUPLICATES BOOST_RPATH_DIRS)
        set_target_properties(bsatool PROPERTIES
            BUILD_RPATH "${BOOST_RPATH_DIRS}"
            BUILD_WITH_INSTALL_RPATH FALSE
        )
        message(STATUS "bsatool: Added Boost rpath directories: ${BOOST_RPATH_DIRS}")
    endif()
endif()

if (WIN32)
    target_sources(bsatool PRIVATE ${CMAKE_SOURCE_DIR}/files/windows/other-apps.manifest)
endif()

if (BUILD_WITH_CODE_COVERAGE)
    target_compile_options(bsatool PRIVATE --coverage)
    target_link_libraries(bsatool gcov)
endif()

if (WIN32)
    install(TARGETS bsatool RUNTIME DESTINATION ".")
endif()

if (MSVC AND PRECOMPILE_HEADERS_WITH_MSVC)
    target_precompile_headers(bsatool PRIVATE
        <filesystem>
        <fstream>
        <vector>
    )
endif()
