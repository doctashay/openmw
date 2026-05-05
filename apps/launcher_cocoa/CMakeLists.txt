set(LAUNCHER_COCOA
    main.mm
)

openmw_add_executable(openmw-launcher-cocoa
    ${LAUNCHER_COCOA}
)

target_link_libraries(openmw-launcher-cocoa
    components
    local_tinyxml
    "-framework Cocoa"
)

if (BUILD_WITH_CODE_COVERAGE)
    target_compile_options(openmw-launcher-cocoa PRIVATE --coverage)
    target_link_libraries(openmw-launcher-cocoa gcov)
endif()
