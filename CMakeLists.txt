cmake_minimum_required(VERSION 3.16.0)

#  set the timestamps of extracted contents to the time of extraction
# remove if cmake version is >= 3.24
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

project(OpenMW)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(GNUInstallDirs)

option(OPENMW_GL4ES_MANUAL_INIT "Manually initialize gl4es. This is more reliable on platforms without a windowing system. Requires gl4es to be configured with -DNOEGL=ON -DNO_LOADER=ON -DNO_INIT_CONSTRUCTOR=ON." OFF)
if(OPENMW_GL4ES_MANUAL_INIT)
    add_definitions(-DOPENMW_GL4ES_MANUAL_INIT)
endif()

if (APPLE OR WIN32)
    set(DEPLOY_QT_TRANSLATIONS_DEFAULT ON)
else ()
    set(DEPLOY_QT_TRANSLATIONS_DEFAULT OFF)
endif ()

option(DEPLOY_QT_TRANSLATIONS "Deploy standard Qt translations to resources folder. Needed when OpenMW applications are deployed with Qt libraries" ${DEPLOY_QT_TRANSLATIONS_DEFAULT})

# Apps and tools
option(BUILD_OPENMW             "Build OpenMW" ON)
option(BUILD_LAUNCHER           "Build Launcher" ON)
option(BUILD_WIZARD             "Build Installation Wizard" ON)
option(BUILD_MWINIIMPORTER      "Build MWiniImporter" ON)
option(BUILD_OPENCS             "Build OpenMW Construction Set" ON)
option(BUILD_ESSIMPORTER        "Build ESS (Morrowind save game) importer" ON)
option(BUILD_BSATOOL            "Build BSA extractor" ON)
option(BUILD_ESMTOOL            "Build ESM inspector" ON)
option(BUILD_NIFTEST            "Build nif file tester" ON)
option(BUILD_DOCS               "Build documentation." OFF )
option(BUILD_WITH_CODE_COVERAGE "Enable code coverage with gconv" OFF)
option(BUILD_COMPONENTS_TESTS   "Build components library tests" OFF)
option(BUILD_BENCHMARKS         "Build benchmarks with Google Benchmark" OFF)
option(BUILD_NAVMESHTOOL        "Build navmesh tool" ON)
option(BUILD_BULLETOBJECTTOOL   "Build Bullet object tool" ON)
option(BUILD_OPENCS_TESTS       "Build OpenMW Construction Set tests" OFF)
option(BUILD_OPENMW_TESTS       "Build OpenMW tests" OFF)
option(PRECOMPILE_HEADERS_WITH_MSVC "Precompile most common used headers with MSVC (alternative to ccache)" ON)

set(OpenGL_GL_PREFERENCE LEGACY)  # Use LEGACY as we use GL2; GLNVD is for GL3 and up.

# USE_QT - disabled by default, user can enable if needed
# First check if user explicitly provided USE_QT on command line
if (DEFINED USE_QT)
    # User explicitly set USE_QT, respect their choice
    message(STATUS "USE_QT explicitly set to: ${USE_QT}")
else()
    # Default to FALSE - Qt disabled
    set(USE_QT FALSE)
    message(STATUS "USE_QT disabled by default (set USE_QT=ON to enable)")
endif()

# Disable Qt-dependent apps if Qt is disabled
if (NOT USE_QT)
    if (BUILD_LAUNCHER)
        message(STATUS "Disabling BUILD_LAUNCHER (requires Qt)")
        set(BUILD_LAUNCHER OFF CACHE BOOL "Build Launcher" FORCE)
    endif()
    if (BUILD_OPENCS)
        message(STATUS "Disabling BUILD_OPENCS (requires Qt)")
        set(BUILD_OPENCS OFF CACHE BOOL "Build OpenMW Construction Set" FORCE)
    endif()
    if (BUILD_WIZARD)
        message(STATUS "Disabling BUILD_WIZARD (requires Qt)")
        set(BUILD_WIZARD OFF CACHE BOOL "Build Installation Wizard" FORCE)
    endif()
    if (BUILD_OPENCS_TESTS)
        message(STATUS "Disabling BUILD_OPENCS_TESTS (requires Qt)")
        set(BUILD_OPENCS_TESTS OFF CACHE BOOL "Build OpenMW Construction Set tests" FORCE)
    endif()
endif()

# If the user doesn't supply a CMAKE_BUILD_TYPE via command line, choose one for them.
IF(NOT CMAKE_BUILD_TYPE)
    SET(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING
        "Choose the type of build, options are: None(CMAKE_CXX_FLAGS or CMAKE_C_FLAGS used) Debug Release RelWithDebInfo MinSizeRel."
        FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS None Debug Release RelWithDebInfo MinSizeRel)
ENDIF()

if (APPLE)
    set(CMAKE_FIND_FRAMEWORK LAST) # prefer dylibs over frameworks
    set(APP_BUNDLE_NAME "${CMAKE_PROJECT_NAME}.app")

    set(APP_BUNDLE_DIR "${OpenMW_BINARY_DIR}/${APP_BUNDLE_NAME}")
    
    # macOS 10.5 Leopard and PowerPC support
    option(OPENMW_MACOSX_10_5_BUILD "Build for macOS 10.5 Leopard" OFF)
    option(OPENMW_POWERPC_BUILD "Build for PowerPC architecture" OFF)
    
    # Auto-detect if deployment target is 10.5 or earlier
    if(CMAKE_OSX_DEPLOYMENT_TARGET)
        if(CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS "10.6")
            set(OPENMW_MACOSX_10_5 TRUE)
            message(STATUS "Detected macOS 10.5 build (deployment target: ${CMAKE_OSX_DEPLOYMENT_TARGET})")
        endif()
    endif()
    
    # Check for PowerPC architecture
    if(CMAKE_OSX_ARCHITECTURES)
        string(TOUPPER "${CMAKE_OSX_ARCHITECTURES}" ARCH_UPPER)
        if(ARCH_UPPER MATCHES "PPC|POWERPC")
            set(OPENMW_POWERPC_BUILD TRUE)
            message(STATUS "Detected PowerPC architecture: ${CMAKE_OSX_ARCHITECTURES}")
        endif()
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "powerpc|ppc")
        set(OPENMW_POWERPC_BUILD TRUE)
        message(STATUS "Detected PowerPC architecture from system processor")
    endif()
    
    # Explicit override options
    if(OPENMW_MACOSX_10_5_BUILD)
        set(OPENMW_MACOSX_10_5 TRUE)
    endif()
    
    if(OPENMW_MACOSX_10_5)
        message(STATUS "Configuring for macOS 10.5 Leopard")
        
        # Force deployment target to 10.5
        if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
            set(CMAKE_OSX_DEPLOYMENT_TARGET "10.5" CACHE STRING "macOS deployment target" FORCE)
        elseif(CMAKE_OSX_DEPLOYMENT_TARGET VERSION_GREATER "10.5")
            message(WARNING "Deployment target ${CMAKE_OSX_DEPLOYMENT_TARGET} is newer than 10.5, forcing to 10.5")
            set(CMAKE_OSX_DEPLOYMENT_TARGET "10.5" CACHE STRING "macOS deployment target" FORCE)
        endif()
        
        # SDK path configuration
        if(DEFINED ENV{MACOSX_SDK_PATH})
            set(CMAKE_OSX_SYSROOT "$ENV{MACOSX_SDK_PATH}" CACHE PATH "macOS SDK path")
        elseif(EXISTS "/Developer/SDKs/MacOSX10.5.sdk")
            set(CMAKE_OSX_SYSROOT "/Developer/SDKs/MacOSX10.5.sdk" CACHE PATH "macOS SDK path")
        elseif(EXISTS "/Developer/SDKs/MacOSX10.5.sdk")
            set(CMAKE_OSX_SYSROOT "/Developer/SDKs/MacOSX10.5.sdk" CACHE PATH "macOS SDK path")
        elseif(EXISTS "/opt/local/libexec/SDKs/MacOSX10.5.sdk")
            set(CMAKE_OSX_SYSROOT "/opt/local/libexec/SDKs/MacOSX10.5.sdk" CACHE PATH "macOS SDK path")
        else()
            message(WARNING "macOS 10.5 SDK not found. Please set MACOSX_SDK_PATH environment variable")
        endif()
        
        if(CMAKE_OSX_SYSROOT)
            message(STATUS "Using macOS SDK: ${CMAKE_OSX_SYSROOT}")
        endif()
        
        # Compiler flags for 10.5
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mmacosx-version-min=10.5")
        set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mmacosx-version-min=10.5")
        
        # Define macros for 10.5 API availability
        add_definitions(-DMAC_OS_X_VERSION_MIN_REQUIRED=1050)
        add_definitions(-DMAC_OS_X_VERSION_MAX_ALLOWED=1050)
        # Also define the underscored version used by some code
        add_definitions(-D__MAC_OS_X_VERSION_MIN_REQUIRED=1050)
        add_definitions(-D__MAC_OS_X_VERSION_MAX_ALLOWED=1050)
        # Define OPENMW_MACOSX_10_5 for code to use
        add_definitions(-DOPENMW_MACOSX_10_5=1)
    endif()
    
    if(OPENMW_POWERPC_BUILD)
        message(STATUS "Building for PowerPC architecture")
        if(NOT CMAKE_OSX_ARCHITECTURES)
            # Default to 32-bit PowerPC for 10.5
            set(CMAKE_OSX_ARCHITECTURES "ppc" CACHE STRING "macOS architectures" FORCE)
        endif()
    endif()
endif (APPLE)

set(CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake/)

if (ANDROID)
    set(CMAKE_FIND_ROOT_PATH ${OPENMW_DEPENDENCIES_DIR} "${CMAKE_FIND_ROOT_PATH}")
endif()

# Version
message(STATUS "Configuring OpenMW...")

set(OPENMW_VERSION_MAJOR 0)
set(OPENMW_VERSION_MINOR 51)
set(OPENMW_VERSION_RELEASE 0)
set(OPENMW_LUA_API_REVISION 111)
set(OPENMW_POSTPROCESSING_API_REVISION 4)

set(OPENMW_VERSION_COMMITHASH "")
set(OPENMW_VERSION_TAGHASH "")
set(OPENMW_VERSION_COMMITDATE "")

set(OPENMW_VERSION "${OPENMW_VERSION_MAJOR}.${OPENMW_VERSION_MINOR}.${OPENMW_VERSION_RELEASE}")

set(OPENMW_DOC_BASEURL "https://openmw.readthedocs.io/en/")

set(GIT_CHECKOUT FALSE)
if(EXISTS ${PROJECT_SOURCE_DIR}/.git)
    find_package(Git)

    if(GIT_FOUND)
        set(GIT_CHECKOUT TRUE)
    else(GIT_FOUND)
        message(WARNING "Git executable not found")
    endif(GIT_FOUND)

    if(GIT_FOUND)
        execute_process (
                COMMAND ${GIT_EXECUTABLE} log -1 --format='%aI'
                WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
                RESULT_VARIABLE EXITCODE3
                OUTPUT_VARIABLE OPENMW_VERSION_COMMITDATE
                OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(NOT EXITCODE3)
            string(SUBSTRING ${OPENMW_VERSION_COMMITDATE} 1 10 OPENMW_VERSION_COMMITDATE)
        endif(NOT EXITCODE3)
    endif(GIT_FOUND)
endif(EXISTS ${PROJECT_SOURCE_DIR}/.git)

# Macros
include(OpenMWMacros)
include(WholeArchive)

# doxygen main page

configure_file ("${OpenMW_SOURCE_DIR}/docs/mainpage.hpp.cmake" "${OpenMW_BINARY_DIR}/docs/mainpage.hpp")

option(QT_STATIC "Link static build of Qt into the binaries" FALSE)

option(OPENMW_USE_SYSTEM_BULLET "Use system provided bullet physics library" ON)
if(OPENMW_USE_SYSTEM_BULLET)
    set(_bullet_static_default OFF)
else()
    set(_bullet_static_default ON)
endif()
option(BULLET_STATIC "Link static build of Bullet into the binaries" ${_bullet_static_default})

option(OPENMW_USE_SYSTEM_OSG "Use system provided OpenSceneGraph libraries" ON)
if(OPENMW_USE_SYSTEM_OSG)
    set(_osg_static_default OFF)
else()
    set(_osg_static_default ON)
endif()
option(OSG_STATIC "Link static build of OpenSceneGraph into the binaries" ${_osg_static_default})

option(OPENMW_USE_SYSTEM_MYGUI "Use system provided mygui library" ON)
if(OPENMW_USE_SYSTEM_MYGUI)
    set(_mygui_static_default OFF)
else()
    set(_mygui_static_default ON)
endif()
option(MYGUI_STATIC "Link static build of Mygui into the binaries" ${_mygui_static_default})

option(OPENMW_USE_SYSTEM_RECASTNAVIGATION "Use system provided recastnavigation library" OFF)
if(OPENMW_USE_SYSTEM_RECASTNAVIGATION)
    set(_recastnavigation_static_default OFF)
    find_package(RecastNavigation REQUIRED CONFIG)
else()
    set(_recastnavigation_static_default ON)
endif()
option(RECASTNAVIGATION_STATIC "Build recastnavigation static libraries" ${_recastnavigation_static_default})

option(OPENMW_USE_SYSTEM_SQLITE3 "Use system provided SQLite3 library" ON)

option(OPENMW_USE_SYSTEM_BENCHMARK "Use system Google Benchmark library." OFF)
option(OPENMW_USE_SYSTEM_GOOGLETEST "Use system Google Test library." OFF)

option(OPENMW_UNITY_BUILD "Use fewer compilation units to speed up compile time" ON)
option(OPENMW_LTO_BUILD "Build OpenMW with Link-Time Optimization (Needs ~2GB of RAM)" OFF)

# OS X deployment
option(OPENMW_OSX_DEPLOYMENT OFF)

if (MSVC)
    option(OPENMW_MP_BUILD "Build OpenMW with /MP flag" OFF)
    if (OPENMW_MP_BUILD)
        add_compile_options(/MP)
    endif()

    # \bigobj is required:
    #  1) for OPENMW_UNITY_BUILD;
    #  2) to compile lua bindings in components, openmw and tests, because sol3 is heavily templated.
    # there should be no relevant downsides to having it on:
    # https://docs.microsoft.com/en-us/cpp/build/reference/bigobj-increase-number-of-sections-in-dot-obj-file
    add_compile_options(/bigobj)

    add_compile_options(/Zc:__cplusplus)

    if (CMAKE_CXX_COMPILER_LAUNCHER OR CMAKE_C_COMPILER_LAUNCHER)
        if (CMAKE_GENERATOR MATCHES "Visual Studio")
            message(STATUS "A compiler launcher was specified, but will be unused by the current generator (${CMAKE_GENERATOR})")
        else()
            foreach (config_lower ${CMAKE_CONFIGURATION_TYPES})
                string(TOUPPER "${config_lower}" config)
                if (CMAKE_C_COMPILER_LAUNCHER STREQUAL "ccache")
                    string(REPLACE "/Zi" "/Z7" CMAKE_C_FLAGS_${config} "${CMAKE_C_FLAGS_${config}}")
                endif()
                if (CMAKE_CXX_COMPILER_LAUNCHER STREQUAL "ccache")
                    string(REPLACE "/Zi" "/Z7" CMAKE_CXX_FLAGS_${config} "${CMAKE_CXX_FLAGS_${config}}")
                endif()
            endforeach()
        endif()
    endif()
endif()

# Set up common paths
if (APPLE)
    set(OPENMW_RESOURCE_FILES "../Resources/resources" CACHE PATH "location of OpenMW resources files")
elseif(UNIX)
    # Paths
    SET(BINDIR "${CMAKE_INSTALL_PREFIX}/bin" CACHE PATH "Where to install binaries")
    SET(LIBDIR "${CMAKE_INSTALL_PREFIX}/lib${LIB_SUFFIX}" CACHE PATH "Where to install libraries")
    SET(DATAROOTDIR "${CMAKE_INSTALL_DATAROOTDIR}" CACHE PATH "Sets the root of data directories to a non-default location")
    SET(GLOBAL_DATA_PATH "${CMAKE_INSTALL_PREFIX}/share/games/" CACHE PATH "Set data path prefix")
    SET(DATADIR "${GLOBAL_DATA_PATH}/openmw" CACHE PATH "Sets the openmw data directories to a non-default location")
    SET(ICONDIR "${DATAROOTDIR}/pixmaps" CACHE PATH "Set icon dir")
    SET(LICDIR "${DATAROOTDIR}/licenses/openmw" CACHE PATH "Sets the openmw license directory to a non-default location.")
    IF("${CMAKE_INSTALL_PREFIX}" STREQUAL "/usr")
        SET(GLOBAL_CONFIG_PATH "/etc/" CACHE PATH "Set config dir prefix")
    ELSE()
        SET(GLOBAL_CONFIG_PATH "${CMAKE_INSTALL_PREFIX}/etc/" CACHE PATH "Set config dir prefix")
    ENDIF()
    SET(SYSCONFDIR "${GLOBAL_CONFIG_PATH}/openmw" CACHE PATH "Set config dir")

    set(OPENMW_RESOURCE_FILES "${DATADIR}/resources" CACHE PATH "location of OpenMW resources files")
else()
    set(OPENMW_RESOURCE_FILES "resources" CACHE PATH "location of OpenMW resources files")
endif(APPLE)

if (WIN32)
    option(USE_DEBUG_CONSOLE "Whether a console should be displayed if OpenMW isn't launched from the command line. Does not affect the Release configuration." ON)
endif()

if(MSVC)
    add_compile_options("/utf-8")
endif()

# Dependencies
if (APPLE)
    # Force CMake to use the installed version of OpenGL on macOS
    set(_SAVE_CMAKE_FIND_FRAMEWORK ${CMAKE_FIND_FRAMEWORK})
    set(CMAKE_FIND_FRAMEWORK ONLY)
    find_package(OpenGL REQUIRED)
    set(CMAKE_FIND_FRAMEWORK ${_SAVE_CMAKE_FIND_FRAMEWORK})
    unset(_SAVE_CMAKE_FIND_FRAMEWORK)
else()
    find_package(OpenGL REQUIRED)
endif()

find_package(LZ4 QUIET)
if(NOT LZ4_FOUND)
    message(FATAL_ERROR "LZ4 library is required but not found. Please install LZ4 via your package manager.")
endif()

if (USE_QT)
    # Qt version selection for macOS 10.5 and PowerPC
    # Default to Qt4 for macOS 10.5 and PowerPC, Qt6 otherwise
    if(OPENMW_MACOSX_10_5 OR OPENMW_POWERPC_BUILD)
        set(OPENMW_QT_VERSION_DEFAULT 4)
        if(OPENMW_MACOSX_10_5)
            message(STATUS "macOS 10.5 detected: defaulting to Qt4")
        else()
            message(STATUS "PowerPC build detected: defaulting to Qt4")
        endif()
    else()
        set(OPENMW_QT_VERSION_DEFAULT 6)
    endif()
    option(OPENMW_QT_VERSION "Qt version to use (4 or 6)" ${OPENMW_QT_VERSION_DEFAULT})
    
    if(OPENMW_MACOSX_10_5 OR OPENMW_POWERPC_BUILD)
        # macOS 10.5 and PowerPC require Qt4 - force it even if user tries to override
        if(NOT OPENMW_QT_VERSION EQUAL 4)
            message(WARNING "macOS 10.5/PowerPC only supports Qt4, forcing Qt4 (ignoring Qt version ${OPENMW_QT_VERSION})")
            set(OPENMW_QT_VERSION 4 CACHE STRING "Qt version" FORCE)
        endif()
        if(OPENMW_MACOSX_10_5)
            message(STATUS "macOS 10.5 build: using Qt4")
        else()
            message(STATUS "PowerPC build: using Qt4")
        endif()
    endif()
    
    if(OPENMW_QT_VERSION EQUAL 4)
        find_package(Qt4 REQUIRED COMPONENTS QtCore QtGui QtOpenGL QtNetwork QtSvg)
        set(QT_VERSION_MAJOR 4)
        set(USE_QT4 TRUE CACHE BOOL "Using Qt4" FORCE)
        message(STATUS "Using Qt4")
    else()
        find_package(QT REQUIRED COMPONENTS Core NAMES Qt6)
        find_package(Qt6 COMPONENTS Core Widgets Network OpenGL OpenGLWidgets LinguistTools Svg REQUIRED)
        set(USE_QT4 FALSE CACHE BOOL "Using Qt4" FORCE)
        message(STATUS "Using Qt${QT_VERSION}")
    endif()
else()
    set(USE_QT4 FALSE CACHE BOOL "Using Qt4" FORCE)
endif()

set(USED_OSG_COMPONENTS
    osgAnimation
    osgDB
    osgGA
    osgFX
    osgParticle
    osgText
    osgUtil
    osgShadow
    osgSim
    osgViewer
    )
set(USED_OSG_PLUGINS
    osgdb_bmp
    osgdb_dae
    osgdb_dds
    osgdb_freetype
    osgdb_jpeg
    osgdb_osg
    osgdb_png
    osgdb_serializers_osg
    osgdb_tga)

if(NOT COLLADA_DOM_VERSION_MAJOR)
    set(COLLADA_DOM_VERSION_MAJOR 2)
endif()

if(NOT COLLADA_DOM_VERSION_MINOR)
    set(COLLADA_DOM_VERSION_MINOR 5)
endif()

find_package(collada_dom 2.5 QUIET)
if(NOT collada_dom_FOUND)
    message(STATUS "collada_dom not found - some features may be unavailable")
endif()

option(OPENMW_USE_SYSTEM_ICU "Use system ICU library instead of internal. If disabled, requires autotools" ON)
if(OPENMW_USE_SYSTEM_ICU)
    find_package(ICU QUIET COMPONENTS uc i18n data)
    if(NOT ICU_FOUND)
        if(OPENMW_MACOSX_10_5)
            message(WARNING "System ICU not found. Internal ICU build requires autotools (autoconf, automake, libtool).")
            message(WARNING "It is STRONGLY recommended to install ICU via MacPorts: sudo port install icu")
            message(WARNING "If you proceed without ICU, some features may be unavailable.")
            # For macOS 10.5, we should probably fail if ICU is not available
            # But let's make it a warning for now and let the build attempt continue
        else()
            message(STATUS "System ICU not found, will build internally")
        endif()
        set(OPENMW_USE_SYSTEM_ICU OFF)
    endif()
endif()

option(OPENMW_USE_SYSTEM_YAML_CPP "Use system yaml-cpp library instead of internal." ON)
if(OPENMW_USE_SYSTEM_YAML_CPP)
    set(_yaml_cpp_static_default OFF)
    find_package(yaml-cpp QUIET)
    if(NOT yaml-cpp_FOUND)
        message(STATUS "System yaml-cpp not found, will build internally")
        set(OPENMW_USE_SYSTEM_YAML_CPP OFF)
        set(_yaml_cpp_static_default ON)
    endif()
else()
    set(_yaml_cpp_static_default ON)
endif()
option(YAML_CPP_STATIC "Link static build of yaml-cpp into the binaries" ${_yaml_cpp_static_default})

if ((BUILD_COMPONENTS_TESTS OR BUILD_OPENCS_TESTS OR BUILD_OPENMW_TESTS) AND OPENMW_USE_SYSTEM_GOOGLETEST)
    find_package(GTest 1.10 QUIET)
    find_package(GMock 1.10 QUIET)
    if(NOT GTest_FOUND OR NOT GMock_FOUND)
        message(STATUS "System GTest/GMock not found, will build internally")
        set(OPENMW_USE_SYSTEM_GOOGLETEST OFF)
    endif()
endif()

add_subdirectory(extern)

# Sound setup

# Require at least ffmpeg 3.2 for now
SET(FFVER_OK FALSE)

find_package(FFmpeg REQUIRED COMPONENTS AVCODEC AVFORMAT AVUTIL SWSCALE SWRESAMPLE)

if(FFmpeg_FOUND)
    SET(FFVER_OK TRUE)

    # Can not detect FFmpeg version on Windows or Android for now
    if (NOT WIN32 AND NOT ANDROID)
        if(FFmpeg_AVFORMAT_VERSION VERSION_LESS "57.56.100")
            message(STATUS "libavformat is too old! (${FFmpeg_AVFORMAT_VERSION}, wanted 57.56.100)")
            set(FFVER_OK FALSE)
        endif()
        if(FFmpeg_AVCODEC_VERSION VERSION_LESS "57.64.100")
            message(STATUS "libavcodec is too old! (${FFmpeg_AVCODEC_VERSION}, wanted 57.64.100)")
            set(FFVER_OK FALSE)
        endif()
        if(FFmpeg_AVUTIL_VERSION VERSION_LESS "55.34.100")
            message(STATUS "libavutil is too old! (${FFmpeg_AVUTIL_VERSION}, wanted 55.34.100)")
            set(FFVER_OK FALSE)
        endif()
        if(FFmpeg_SWSCALE_VERSION VERSION_LESS "4.2.100")
            message(STATUS "libswscale is too old! (${FFmpeg_SWSCALE_VERSION}, wanted 4.2.100)")
            set(FFVER_OK FALSE)
        endif()
        if(FFmpeg_SWRESAMPLE_VERSION VERSION_LESS "2.3.100")
            message(STATUS "libswresample is too old! (${FFmpeg_SWRESAMPLE_VERSION}, wanted 2.3.100)")
            set(FFVER_OK FALSE)
        endif()
    endif()

    if(NOT FFVER_OK AND NOT APPLE)  # unable to detect on version on MacOS < 11.0
        if(OPENMW_MACOSX_10_5)
            message(WARNING "FFmpeg version may be too old (${FFmpeg_AVFORMAT_VERSION}), but continuing for macOS 10.5 compatibility")
        else()
            message(FATAL_ERROR "FFmpeg version is too old, 3.2 is required" )
        endif()
    endif()
endif()

if(NOT FFmpeg_FOUND)
    message(FATAL_ERROR "FFmpeg was not found" )
endif()

if(WIN32)
    message("Can not detect FFmpeg version, at least the 3.2 is required" )
endif()

# Required for building the FFmpeg headers
add_definitions(-D__STDC_CONSTANT_MACROS)

# TinyXML
option(USE_SYSTEM_TINYXML "Use system TinyXML library instead of internal." OFF)
if (USE_SYSTEM_TINYXML)
    find_package(TinyXML REQUIRED)
    add_definitions (-DTIXML_USE_STL)
    include_directories(SYSTEM ${TinyXML_INCLUDE_DIRS})
endif()

# Platform specific
if (WIN32)
    # Suppress WinMain(), provided by SDL
    add_definitions(-DSDL_MAIN_HANDLED)

    # Get rid of useless crud from windows.h
    add_definitions(
        -DNOMINMAX # name conflict with std::min, std::max
        -DWIN32_LEAN_AND_MEAN
        -DNOMB # name conflict with MWGui::MessageBox
        -DNOGDI # name conflict with osgAnimation::MorphGeometry::RELATIVE
    )
endif()

if(OPENMW_USE_SYSTEM_BULLET)
    set(REQUIRED_BULLET_VERSION 286) # Bullet 286 required due to runtime bugfixes for btCapsuleShape
    if (DEFINED ENV{TRAVIS_BRANCH} OR DEFINED ENV{APPVEYOR})
        set(REQUIRED_BULLET_VERSION 283) # but for build testing, 283 is fine
    endif()

    # First, try BulletConfig-float64.cmake which comes with Debian derivatives.
    # This file does not define the Bullet version in a CMake-friendly way.
    find_package(Bullet CONFIGS BulletConfig-float64.cmake QUIET COMPONENTS BulletCollision LinearMath)
    if (BULLET_FOUND)
        string(REPLACE "." "" _bullet_version_num ${BULLET_VERSION_STRING})
        if (_bullet_version_num VERSION_LESS REQUIRED_BULLET_VERSION)
            message(WARNING "System bullet version too old (${_bullet_version_num}), required ${REQUIRED_BULLET_VERSION}. Falling back to internal build.")
            set(OPENMW_USE_SYSTEM_BULLET OFF)
        else()
            # Fix the relative include:
            set(BULLET_INCLUDE_DIRS "${BULLET_ROOT_DIR}/${BULLET_INCLUDE_DIRS}")
            include(FindPackageMessage)
            find_package_message(Bullet "Found Bullet: ${BULLET_LIBRARIES} ${BULLET_VERSION_STRING}" "${BULLET_VERSION_STRING}-float64")
        endif()
    else()
        # Try standard find_package
        find_package(Bullet ${REQUIRED_BULLET_VERSION} QUIET COMPONENTS BulletCollision LinearMath)
        if(NOT BULLET_FOUND)
            message(STATUS "System Bullet not found, will build internally")
            set(OPENMW_USE_SYSTEM_BULLET OFF)
        endif()
    endif()

    if(OPENMW_USE_SYSTEM_BULLET)
        # Only link the Bullet libraries that we need:
        string(REGEX MATCHALL "((optimized|debug);)?[^;]*(BulletCollision|LinearMath)[^;]*" BULLET_LIBRARIES "${BULLET_LIBRARIES}")

        include(cmake/CheckBulletPrecision.cmake)
        if (HAS_DOUBLE_PRECISION_BULLET)
            message(STATUS "Bullet uses double precision")
        else()
            message(WARNING "Bullet does not use double precision. Falling back to internal build.")
            set(OPENMW_USE_SYSTEM_BULLET OFF)
        endif()
    endif()
endif()

if (NOT WIN32 AND BUILD_WIZARD) # windows users can just run the morrowind installer
    find_package(LIBUNSHIELD QUIET) # required only for non win32 when building openmw-wizard
    if(LIBUNSHIELD_FOUND)
        set(OPENMW_USE_UNSHIELD TRUE)
    else()
        message(WARNING "LIBUNSHIELD not found - wizard will not be able to extract game files from installers")
        message(WARNING "Users will need to manually extract game files")
        set(OPENMW_USE_UNSHIELD FALSE)
    endif()
endif()

# Fix for not visible pthreads functions for linker with glibc 2.15
if (UNIX AND NOT APPLE)
    find_package (Threads)
endif()

# Look for stdint.h
include(CheckIncludeFile)
check_include_file(stdint.h HAVE_STDINT_H)
if(NOT HAVE_STDINT_H)
    unset(HAVE_STDINT_H CACHE)
    message(FATAL_ERROR "stdint.h was not found" )
endif()

if(OPENMW_USE_SYSTEM_OSG)
    find_package(OpenSceneGraph 3.6.5 QUIET COMPONENTS ${USED_OSG_COMPONENTS})  # Bump to 3.6.6 when released

    if(NOT OpenSceneGraph_FOUND)
        message(STATUS "System OpenSceneGraph not found, will build internally")
        set(OPENMW_USE_SYSTEM_OSG OFF)
        set(_osg_static_default ON)
    else()
        if(OSG_STATIC)
            find_package(OSGPlugins QUIET COMPONENTS ${USED_OSG_PLUGINS})
            if(NOT OSGPlugins_FOUND)
                message(STATUS "System OSGPlugins not found, will build OSG internally")
                set(OPENMW_USE_SYSTEM_OSG OFF)
                set(_osg_static_default ON)
            endif()
        endif()
    endif()
endif()

# Always add OSG include directories (for both system and internal builds)
if(OPENSCENEGRAPH_INCLUDE_DIRS)
    include_directories(BEFORE SYSTEM ${OPENSCENEGRAPH_INCLUDE_DIRS})
endif()

if(OSG_STATIC)
    add_definitions(-DOSG_LIBRARY_STATIC)
endif()

include(cmake/CheckOsgMultiview.cmake)
if(HAVE_MULTIVIEW)
    add_definitions(-DOSG_HAS_MULTIVIEW)
endif(HAVE_MULTIVIEW)

set(BOOST_COMPONENTS iostreams program_options)

# Explicitly use shared libraries (MacPorts boost176 is built with +no_static)
set(Boost_USE_STATIC_LIBS OFF)
set(Boost_USE_STATIC_RUNTIME OFF)

# Try CONFIG mode first (modern Boost), fallback to MODULE mode (older installations/MacPorts)
find_package(Boost 1.70.0 CONFIG QUIET COMPONENTS ${BOOST_COMPONENTS} OPTIONAL_COMPONENTS ${BOOST_OPTIONAL_COMPONENTS})
if(NOT Boost_FOUND)
    # Fallback to MODULE mode for older Boost installations or MacPorts
    find_package(Boost 1.70.0 MODULE QUIET COMPONENTS ${BOOST_COMPONENTS} OPTIONAL_COMPONENTS ${BOOST_OPTIONAL_COMPONENTS})
endif()
if(NOT Boost_FOUND)
    message(FATAL_ERROR "Boost 1.70.0 or later is required. Please install Boost via MacPorts:\n  sudo port install boost\nOr set Boost_ROOT to the Boost installation directory.")
endif()

# Create imported targets if they don't exist (MODULE mode doesn't create them)
if(NOT TARGET Boost::program_options)
    add_library(Boost::program_options IMPORTED UNKNOWN)
    set(BOOST_PO_FOUND FALSE)
    set(BOOST_PO_LIB "")
    
    # Try component-specific variables first
    if(Boost_PROGRAM_OPTIONS_LIBRARY_RELEASE)
        set_target_properties(Boost::program_options PROPERTIES
            IMPORTED_LOCATION_RELEASE "${Boost_PROGRAM_OPTIONS_LIBRARY_RELEASE}")
        set(BOOST_PO_FOUND TRUE)
        set(BOOST_PO_LIB "${Boost_PROGRAM_OPTIONS_LIBRARY_RELEASE}")
    endif()
    if(Boost_PROGRAM_OPTIONS_LIBRARY_DEBUG)
        set_target_properties(Boost::program_options PROPERTIES
            IMPORTED_LOCATION_DEBUG "${Boost_PROGRAM_OPTIONS_LIBRARY_DEBUG}")
        set(BOOST_PO_FOUND TRUE)
        if(NOT BOOST_PO_LIB)
            set(BOOST_PO_LIB "${Boost_PROGRAM_OPTIONS_LIBRARY_DEBUG}")
        endif()
    endif()
    if(Boost_PROGRAM_OPTIONS_LIBRARY)
        set_target_properties(Boost::program_options PROPERTIES
            IMPORTED_LOCATION "${Boost_PROGRAM_OPTIONS_LIBRARY}")
        set(BOOST_PO_FOUND TRUE)
        if(NOT BOOST_PO_LIB)
            set(BOOST_PO_LIB "${Boost_PROGRAM_OPTIONS_LIBRARY}")
        endif()
    endif()
    
    # Fallback: Extract from Boost_LIBRARIES
    if(NOT BOOST_PO_FOUND AND Boost_LIBRARIES)
        foreach(lib ${Boost_LIBRARIES})
            # Skip generator expressions and keywords
            if(lib MATCHES "program_options" AND NOT lib MATCHES "^(optimized|debug|general)$")
                # Remove generator expression keywords
                string(REGEX REPLACE "^(optimized|debug);" "" clean_lib "${lib}")
                if(EXISTS "${clean_lib}")
                    set_target_properties(Boost::program_options PROPERTIES
                        IMPORTED_LOCATION "${clean_lib}")
                    set(BOOST_PO_FOUND TRUE)
                    set(BOOST_PO_LIB "${clean_lib}")
                    break()
                endif()
            endif()
        endforeach()
    endif()
    
    # Fallback: Construct path from Boost_LIBRARY_DIRS
    if(NOT BOOST_PO_FOUND AND Boost_LIBRARY_DIRS)
        # Try shared library first (since Boost_USE_STATIC_LIBS is OFF)
        find_library(BOOST_PO_LIB_TMP
            NAMES boost_program_options
            PATHS ${Boost_LIBRARY_DIRS}
            NO_DEFAULT_PATH
        )
        if(BOOST_PO_LIB_TMP)
            set_target_properties(Boost::program_options PROPERTIES
                IMPORTED_LOCATION "${BOOST_PO_LIB_TMP}")
            set(BOOST_PO_FOUND TRUE)
            set(BOOST_PO_LIB "${BOOST_PO_LIB_TMP}")
        endif()
    endif()
    
    # Fallback: Use Boost_ROOT if set
    if(NOT BOOST_PO_FOUND AND Boost_ROOT)
        find_library(BOOST_PO_LIB_TMP
            NAMES boost_program_options
            PATHS "${Boost_ROOT}/lib"
            NO_DEFAULT_PATH
        )
        if(BOOST_PO_LIB_TMP)
            set_target_properties(Boost::program_options PROPERTIES
                IMPORTED_LOCATION "${BOOST_PO_LIB_TMP}")
            set(BOOST_PO_FOUND TRUE)
            set(BOOST_PO_LIB "${BOOST_PO_LIB_TMP}")
        endif()
    endif()
    
    if(Boost_INCLUDE_DIRS)
        set_target_properties(Boost::program_options PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${Boost_INCLUDE_DIRS}")
    endif()
    
    if(NOT BOOST_PO_FOUND)
        message(FATAL_ERROR 
            "Boost::program_options library not found.\n"
            "Boost_PROGRAM_OPTIONS_LIBRARY: ${Boost_PROGRAM_OPTIONS_LIBRARY}\n"
            "Boost_LIBRARIES: ${Boost_LIBRARIES}\n"
            "Boost_LIBRARY_DIRS: ${Boost_LIBRARY_DIRS}\n"
            "Boost_ROOT: ${Boost_ROOT}\n"
            "Please ensure Boost is properly installed and Boost_ROOT is set correctly.")
    endif()
endif()

if(NOT TARGET Boost::iostreams)
    add_library(Boost::iostreams IMPORTED UNKNOWN)
    set(BOOST_IOSTREAMS_FOUND FALSE)
    set(BOOST_IOSTREAMS_LIB "")
    
    # Try component-specific variables first
    if(Boost_IOSTREAMS_LIBRARY_RELEASE)
        set_target_properties(Boost::iostreams PROPERTIES
            IMPORTED_LOCATION_RELEASE "${Boost_IOSTREAMS_LIBRARY_RELEASE}")
        set(BOOST_IOSTREAMS_FOUND TRUE)
        set(BOOST_IOSTREAMS_LIB "${Boost_IOSTREAMS_LIBRARY_RELEASE}")
    endif()
    if(Boost_IOSTREAMS_LIBRARY_DEBUG)
        set_target_properties(Boost::iostreams PROPERTIES
            IMPORTED_LOCATION_DEBUG "${Boost_IOSTREAMS_LIBRARY_DEBUG}")
        set(BOOST_IOSTREAMS_FOUND TRUE)
        if(NOT BOOST_IOSTREAMS_LIB)
            set(BOOST_IOSTREAMS_LIB "${Boost_IOSTREAMS_LIBRARY_DEBUG}")
        endif()
    endif()
    if(Boost_IOSTREAMS_LIBRARY)
        set_target_properties(Boost::iostreams PROPERTIES
            IMPORTED_LOCATION "${Boost_IOSTREAMS_LIBRARY}")
        set(BOOST_IOSTREAMS_FOUND TRUE)
        if(NOT BOOST_IOSTREAMS_LIB)
            set(BOOST_IOSTREAMS_LIB "${Boost_IOSTREAMS_LIBRARY}")
        endif()
    endif()
    
    # Fallback: Extract from Boost_LIBRARIES
    if(NOT BOOST_IOSTREAMS_FOUND AND Boost_LIBRARIES)
        foreach(lib ${Boost_LIBRARIES})
            if(lib MATCHES "iostreams" AND NOT lib MATCHES "^(optimized|debug|general)$")
                string(REGEX REPLACE "^(optimized|debug);" "" clean_lib "${lib}")
                if(EXISTS "${clean_lib}")
                    set_target_properties(Boost::iostreams PROPERTIES
                        IMPORTED_LOCATION "${clean_lib}")
                    set(BOOST_IOSTREAMS_FOUND TRUE)
                    set(BOOST_IOSTREAMS_LIB "${clean_lib}")
                    break()
                endif()
            endif()
        endforeach()
    endif()
    
    # Fallback: Construct path from Boost_LIBRARY_DIRS
    if(NOT BOOST_IOSTREAMS_FOUND AND Boost_LIBRARY_DIRS)
        find_library(BOOST_IOSTREAMS_LIB_TMP
            NAMES boost_iostreams
            PATHS ${Boost_LIBRARY_DIRS}
            NO_DEFAULT_PATH
        )
        if(BOOST_IOSTREAMS_LIB_TMP)
            set_target_properties(Boost::iostreams PROPERTIES
                IMPORTED_LOCATION "${BOOST_IOSTREAMS_LIB_TMP}")
            set(BOOST_IOSTREAMS_FOUND TRUE)
            set(BOOST_IOSTREAMS_LIB "${BOOST_IOSTREAMS_LIB_TMP}")
        endif()
    endif()
    
    # Fallback: Use Boost_ROOT if set
    if(NOT BOOST_IOSTREAMS_FOUND AND Boost_ROOT)
        find_library(BOOST_IOSTREAMS_LIB_TMP
            NAMES boost_iostreams
            PATHS "${Boost_ROOT}/lib"
            NO_DEFAULT_PATH
        )
        if(BOOST_IOSTREAMS_LIB_TMP)
            set_target_properties(Boost::iostreams PROPERTIES
                IMPORTED_LOCATION "${BOOST_IOSTREAMS_LIB_TMP}")
            set(BOOST_IOSTREAMS_FOUND TRUE)
            set(BOOST_IOSTREAMS_LIB "${BOOST_IOSTREAMS_LIB_TMP}")
        endif()
    endif()
    
    if(Boost_INCLUDE_DIRS)
        set_target_properties(Boost::iostreams PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${Boost_INCLUDE_DIRS}")
    endif()
    
    if(NOT BOOST_IOSTREAMS_FOUND)
        message(FATAL_ERROR 
            "Boost::iostreams library not found.\n"
            "Boost_IOSTREAMS_LIBRARY: ${Boost_IOSTREAMS_LIBRARY}\n"
            "Boost_LIBRARIES: ${Boost_LIBRARIES}\n"
            "Boost_LIBRARY_DIRS: ${Boost_LIBRARY_DIRS}\n"
            "Boost_ROOT: ${Boost_ROOT}\n"
            "Please ensure Boost is properly installed and Boost_ROOT is set correctly.")
    endif()
endif()

# For PowerPC builds, verify program_options library has PowerPC architecture
if(APPLE AND (CMAKE_OSX_ARCHITECTURES MATCHES "ppc" OR OPENMW_POWERPC_BUILD))
    # Try to find the actual program_options library file
    if(TARGET Boost::program_options)
        get_target_property(BOOST_PO_LOCATION Boost::program_options LOCATION)
        if(BOOST_PO_LOCATION STREQUAL "BOOST_PO_LOCATION-NOTFOUND")
            # Try alternative method
            get_target_property(BOOST_PO_IMPORTED_LOCATION Boost::program_options IMPORTED_LOCATION)
            if(NOT BOOST_PO_IMPORTED_LOCATION STREQUAL "BOOST_PO_IMPORTED_LOCATION-NOTFOUND")
                set(BOOST_PO_LOCATION "${BOOST_PO_IMPORTED_LOCATION}")
            endif()
        endif()
        if(BOOST_PO_LOCATION AND EXISTS "${BOOST_PO_LOCATION}")
            execute_process(
                COMMAND lipo -info "${BOOST_PO_LOCATION}"
                OUTPUT_VARIABLE BOOST_PO_ARCH_INFO
                ERROR_QUIET
            )
            if(BOOST_PO_ARCH_INFO)
                string(FIND "${BOOST_PO_ARCH_INFO}" "ppc" PPC_POS)
                string(FIND "${BOOST_PO_ARCH_INFO}" "powerpc" POWERPC_POS)
                if(PPC_POS EQUAL -1 AND POWERPC_POS EQUAL -1)
                    message(FATAL_ERROR
                        "BOOST PROGRAM_OPTIONS MISSING POWERPC ARCHITECTURE\n"
                        "The Boost program_options library does not contain PowerPC architecture.\n"
                        "Library: ${BOOST_PO_LOCATION}\n"
                        "Architectures found: ${BOOST_PO_ARCH_INFO}\n"
                        "This will cause linker errors: Undefined symbols for architecture ppc.\n"
                        "SOLUTION: Rebuild Boost for PowerPC using build_boost181_ppc.sh\n"
                        "Then set: export Boost_ROOT=/opt/local/boost181-gcc14-ppc"
                    )
                else()
                    message(STATUS "Boost program_options contains PowerPC architecture")
                endif()
            endif()
        endif()
    endif()
endif()

# Check Boost ABI compatibility for PowerPC/macOS 10.5
# MacPorts Boost may be built with Clang/libc++, but we're using GCC/libstdc++
# IMPORTANT: MacPorts must be configured with 'cxx_stdlib libstdc++' in macports.conf
# and Boost should be installed with compiler=gcc-14 variant to ensure libstdc++ is used
# Detect ABI mismatches and stop the build if incompatible
if(APPLE AND (CMAKE_OSX_ARCHITECTURES MATCHES "ppc" OR OPENMW_POWERPC_BUILD))
    message(STATUS "Checking Boost ABI compatibility...")
    message(STATUS "Boost found: ${Boost_VERSION}")
    message(STATUS "Boost libraries: ${Boost_LIBRARIES}")
    message(STATUS "")
    message(STATUS "NOTE: For MacPorts Boost, ensure 'cxx_stdlib libstdc++' is set in macports.conf")
    message(STATUS "      and install with: sudo port install boost176 compiler=gcc-14")
    message(STATUS "")
    
    # Determine our build's ABI settings
    set(OUR_STDLIB "unknown")
    set(OUR_COMPILER_ID "${CMAKE_CXX_COMPILER_ID}")
    set(OUR_CXX11_ABI "unknown")
    
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|AppleClang")
        # Clang on macOS typically uses libc++
        set(OUR_STDLIB "libc++")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        # GCC uses libstdc++ by default
        set(OUR_STDLIB "libstdc++")
        # GCC 5.1+ defaults to C++11 ABI (value 1)
        # Check if we're explicitly setting it
        if(CMAKE_CXX_FLAGS MATCHES "_GLIBCXX_USE_CXX11_ABI=0")
            set(OUR_CXX11_ABI "0")
        else()
            set(OUR_CXX11_ABI "1")
        endif()
    endif()
    
    message(STATUS "Our build configuration:")
    message(STATUS "  Compiler: ${OUR_COMPILER_ID}")
    message(STATUS "  Standard library: ${OUR_STDLIB}")
    if(OUR_CXX11_ABI STREQUAL "0" OR OUR_CXX11_ABI STREQUAL "1")
        message(STATUS "  C++11 ABI: ${OUR_CXX11_ABI}")
    endif()
    
    # Detect Boost's ABI by examining its libraries
    set(BOOST_STDLIB "unknown")
    set(BOOST_COMPILER_ID "unknown")
    set(BOOST_CXX11_ABI "unknown")
    set(ABI_CHECK_FAILED FALSE)
    
    if(Boost_LIBRARIES)
        list(GET Boost_LIBRARIES 0 FIRST_BOOST_LIB)
        if(EXISTS "${FIRST_BOOST_LIB}")
            # Check architecture first
            execute_process(
                COMMAND lipo -info "${FIRST_BOOST_LIB}"
                OUTPUT_VARIABLE BOOST_ARCH_INFO
                ERROR_QUIET
            )
            if(BOOST_ARCH_INFO)
                message(STATUS "Boost architecture: ${BOOST_ARCH_INFO}")
                # Check if PowerPC architecture is present
                string(FIND "${BOOST_ARCH_INFO}" "ppc" PPC_POS)
                string(FIND "${BOOST_ARCH_INFO}" "powerpc" POWERPC_POS)
                if(PPC_POS EQUAL -1)
                    if(POWERPC_POS EQUAL -1)
                        message(WARNING "Boost library does NOT contain PowerPC architecture!")
                        message(WARNING "Found architectures: ${BOOST_ARCH_INFO}")
                        message(WARNING "This will cause linker errors for PowerPC builds.")
                        message(WARNING "Solution: Rebuild Boost for PowerPC using build_boost181_ppc.sh")
                        set(BOOST_MISSING_PPC TRUE)
                    else()
                        message(STATUS "Boost library contains PowerPC architecture")
                    endif()
                else()
                    message(STATUS "Boost library contains PowerPC architecture")
                endif()
            else()
                message(WARNING "Could not determine Boost library architecture")
            endif()
            
            # Use otool -L to check linked standard library
            execute_process(
                COMMAND otool -L "${FIRST_BOOST_LIB}"
                OUTPUT_VARIABLE BOOST_OTOOL_OUTPUT
                ERROR_QUIET
            )
            
            if(BOOST_OTOOL_OUTPUT)
                # Check for libc++ (Clang's standard library)
                if(BOOST_OTOOL_OUTPUT MATCHES "libc\\+\\+")
                    set(BOOST_STDLIB "libc++")
                    set(BOOST_COMPILER_ID "likely_Clang")
                # Check for libstdc++ (GCC's standard library)
                elseif(BOOST_OTOOL_OUTPUT MATCHES "libstdc\\+\\+")
                    set(BOOST_STDLIB "libstdc++")
                    set(BOOST_COMPILER_ID "likely_GCC")
                endif()
            endif()
            
            # Use nm to check symbol mangling patterns as additional verification
            # _ZSt indicates libstdc++, _ZNSt indicates libc++
            execute_process(
                COMMAND nm -g "${FIRST_BOOST_LIB}" 2>/dev/null | head -20
                OUTPUT_VARIABLE BOOST_NM_OUTPUT
                ERROR_QUIET
            )
            
            if(BOOST_NM_OUTPUT)
                if(BOOST_NM_OUTPUT MATCHES "_ZSt")
                    if(BOOST_STDLIB STREQUAL "unknown")
                        set(BOOST_STDLIB "libstdc++")
                        set(BOOST_COMPILER_ID "likely_GCC")
                    endif()
                elseif(BOOST_NM_OUTPUT MATCHES "_ZNSt")
                    if(BOOST_STDLIB STREQUAL "unknown")
                        set(BOOST_STDLIB "libc++")
                        set(BOOST_COMPILER_ID "likely_Clang")
                    endif()
                endif()
            endif()
            
            # If we still don't know, try to detect C++11 ABI for libstdc++
            if(BOOST_STDLIB STREQUAL "libstdc++")
                # Check for C++11 ABI symbols (new ABI uses different mangling)
                # This is a heuristic - new ABI symbols are longer
                execute_process(
                    COMMAND nm -g "${FIRST_BOOST_LIB}" 2>/dev/null | grep -c "_ZSt" || echo "0"
                    OUTPUT_VARIABLE BOOST_STD_SYMBOL_COUNT
                    ERROR_QUIET
                )
                # If we find many _ZSt symbols, it's likely using C++11 ABI
                # This is not 100% reliable but better than nothing
                if(BOOST_STD_SYMBOL_COUNT)
                    string(STRIP "${BOOST_STD_SYMBOL_COUNT}" BOOST_STD_SYMBOL_COUNT)
                    if(BOOST_STD_SYMBOL_COUNT GREATER "10")
                        set(BOOST_CXX11_ABI "likely_1")
                    else()
                        set(BOOST_CXX11_ABI "likely_0")
                    endif()
                endif()
            endif()
        else()
            set(ABI_CHECK_FAILED TRUE)
            message(WARNING "Boost library not found at: ${FIRST_BOOST_LIB}")
        endif()
    else()
        set(ABI_CHECK_FAILED TRUE)
        message(WARNING "Boost_LIBRARIES is empty")
    endif()
    
    message(STATUS "Boost library analysis:")
    message(STATUS "  Standard library: ${BOOST_STDLIB}")
    message(STATUS "  Compiler: ${BOOST_COMPILER_ID}")
    if(NOT BOOST_CXX11_ABI STREQUAL "unknown")
        message(STATUS "  C++11 ABI: ${BOOST_CXX11_ABI}")
    endif()
    
    # Compare ABIs and determine compatibility
    if(NOT ABI_CHECK_FAILED AND NOT BOOST_STDLIB STREQUAL "unknown")
        set(ABI_MISMATCH FALSE)
        set(CAN_WORKAROUND FALSE)
        set(WORKAROUND_APPLIED FALSE)
        
        # Case 1: libc++ vs libstdc++ - INCOMPATIBLE, no workaround
        if(BOOST_STDLIB STREQUAL "libc++" AND OUR_STDLIB STREQUAL "libstdc++")
            set(ABI_MISMATCH TRUE)
            message(FATAL_ERROR "\n"
                "================================================================================\n"
                "BOOST ABI MISMATCH DETECTED - BUILD CANNOT PROCEED\n"
                "================================================================================\n"
                "Boost was built with: ${BOOST_STDLIB} (${BOOST_COMPILER_ID})\n"
                "OpenMW is building with: ${OUR_STDLIB} (${OUR_COMPILER_ID})\n"
                "\n"
                "These are incompatible - libc++ and libstdc++ cannot be mixed.\n"
                "\n"
                "SOLUTION: Rebuild Boost with the same compiler and standard library:\n"
                "\n"
                "Option 1: Manual build (recommended for PowerPC):\n"
                "  ./build_boost_ppc.sh\n"
                "  export Boost_ROOT=/opt/local/boost-gcc14-ppc\n"
                "\n"
                "Option 2: MacPorts (ensure cxx_stdlib libstdc++ in macports.conf):\n"
                "  # Verify MacPorts config has: cxx_stdlib libstdc++\n"
                "  # Then install with GCC compiler variant:\n"
                "  sudo port -s install boost176 compiler=gcc-14\n"
                "  # Or uninstall and reinstall:\n"
                "  sudo port uninstall boost176\n"
                "  sudo port install boost176 compiler=gcc-14\n"
                "\n"
                "Then rerun CMake with: -D Boost_ROOT=<path_to_boost>\n"
                "\n"
                "To verify Boost's runtime, run:\n"
                "  otool -L $(port file boost176 | grep -A5 'files' | head -1)/lib/libboost_program_options*.dylib\n"
                "================================================================================\n"
            )
        elseif(BOOST_STDLIB STREQUAL "libstdc++" AND OUR_STDLIB STREQUAL "libc++")
            set(ABI_MISMATCH TRUE)
            message(FATAL_ERROR "\n"
                "================================================================================\n"
                "BOOST ABI MISMATCH DETECTED - BUILD CANNOT PROCEED\n"
                "================================================================================\n"
                "Boost was built with: ${BOOST_STDLIB} (${BOOST_COMPILER_ID})\n"
                "OpenMW is building with: ${OUR_STDLIB} (${OUR_COMPILER_ID})\n"
                "\n"
                "These are incompatible - libstdc++ and libc++ cannot be mixed.\n"
                "\n"
                "SOLUTION: Rebuild Boost with Clang/libc++ or switch OpenMW to use libstdc++.\n"
                "================================================================================\n"
            )
        # Case 2: Both use libstdc++ but different C++11 ABI - MAYBE workaround
        elseif(BOOST_STDLIB STREQUAL "libstdc++" AND OUR_STDLIB STREQUAL "libstdc++")
            if(NOT BOOST_CXX11_ABI STREQUAL "unknown" AND NOT OUR_CXX11_ABI STREQUAL "unknown")
                if(BOOST_CXX11_ABI MATCHES "likely_0" AND OUR_CXX11_ABI STREQUAL "1")
                    set(CAN_WORKAROUND TRUE)
                    message(WARNING "\n"
                        "================================================================================\n"
                        "BOOST C++11 ABI MISMATCH DETECTED - ATTEMPTING WORKAROUND\n"
                        "================================================================================\n"
                        "Boost appears to use old C++11 ABI (0), but we're using new ABI (1).\n"
                        "Attempting to match Boost's ABI by setting _GLIBCXX_USE_CXX11_ABI=0\n"
                        "\n"
                        "WARNING: This is a workaround and may cause issues. It's better to rebuild\n"
                        "Boost with matching settings.\n"
                        "================================================================================\n"
                    )
                    add_definitions(-D_GLIBCXX_USE_CXX11_ABI=0)
                    set(WORKAROUND_APPLIED TRUE)
                elseif(BOOST_CXX11_ABI MATCHES "likely_1" AND OUR_CXX11_ABI STREQUAL "0")
                    set(CAN_WORKAROUND TRUE)
                    message(WARNING "\n"
                        "================================================================================\n"
                        "BOOST C++11 ABI MISMATCH DETECTED - ATTEMPTING WORKAROUND\n"
                        "================================================================================\n"
                        "Boost appears to use new C++11 ABI (1), but we're using old ABI (0).\n"
                        "Attempting to match Boost's ABI by setting _GLIBCXX_USE_CXX11_ABI=1\n"
                        "\n"
                        "WARNING: This is a workaround and may cause issues. It's better to rebuild\n"
                        "Boost with matching settings.\n"
                        "================================================================================\n"
                    )
                    add_definitions(-D_GLIBCXX_USE_CXX11_ABI=1)
                    set(WORKAROUND_APPLIED TRUE)
                else()
                    message(STATUS "Boost and OpenMW both use libstdc++ with compatible C++11 ABI settings")
                endif()
            else()
                message(STATUS "Boost and OpenMW both use libstdc++ - ABI should be compatible")
            endif()
        # Case 3: Both use libc++ - should be compatible
        elseif(BOOST_STDLIB STREQUAL "libc++" AND OUR_STDLIB STREQUAL "libc++")
            message(STATUS "Boost and OpenMW both use libc++ - ABI should be compatible")
        endif()
        
        if(NOT ABI_MISMATCH AND NOT WORKAROUND_APPLIED)
            message(STATUS "Boost ABI compatibility check passed")
        endif()
        
        # Check if PowerPC architecture is missing (critical for PowerPC builds)
        if(BOOST_MISSING_PPC)
            message(FATAL_ERROR "\n"
                "================================================================================\n"
                "BOOST MISSING POWERPC ARCHITECTURE - BUILD CANNOT PROCEED\n"
                "================================================================================\n"
                "The Boost libraries found do not contain PowerPC architecture slices.\n"
                "This will cause linker errors with 'Undefined symbols for architecture ppc'.\n"
                "\n"
                "SOLUTION: Rebuild Boost for PowerPC:\n"
                "\n"
                "Option 1: Use the provided build script (recommended):\n"
                "  ./build_boost_ppc.sh\n"
                "  export Boost_ROOT=/opt/local/boost-gcc14-ppc\n"
                "  # Then rerun CMake\n"
                "\n"
                "Option 2: Manual MacPorts build:\n"
                "  sudo port install boost176 compiler=gcc-14\n"
                "  # Ensure MacPorts is configured with 'cxx_stdlib libstdc++' in macports.conf\n"
                "\n"
                "To verify Boost has PowerPC support, run:\n"
                "  lipo -info ${FIRST_BOOST_LIB}\n"
                "  # Should show 'ppc' or 'powerpc' in the output\n"
                "================================================================================\n"
            )
        endif()
    else()
        message(WARNING "Could not fully analyze Boost ABI - proceeding with caution")
        message(WARNING "If you encounter linker errors (vtable errors, undefined symbols),")
        message(WARNING "Boost may have been built with a different compiler/ABI.")
        message(WARNING "Solution: Rebuild Boost with gcc-mp-14 using build_boost_ppc.sh")
    endif()
endif()

if(OPENMW_USE_SYSTEM_MYGUI)
    find_package(MyGUI 3.4.3 QUIET)
    if(NOT MyGUI_FOUND)
        message(STATUS "System MyGUI not found, will build internally")
        set(OPENMW_USE_SYSTEM_MYGUI OFF)
        set(_mygui_static_default ON)
    endif()
endif()
find_package(SDL2 2.0.20 QUIET)
if(NOT SDL2_FOUND)
    message(FATAL_ERROR "SDL2 2.0.20 or later is required but not found. Please install SDL2 via your package manager.")
endif()

find_package(OpenAL QUIET)
if(NOT OpenAL_FOUND)
    message(FATAL_ERROR "OpenAL is required for audio support but not found. Please install OpenAL via your package manager.")
endif()

find_package(ZLIB QUIET)
if(NOT ZLIB_FOUND)
    message(FATAL_ERROR "ZLIB is required but not found. Please install ZLIB via your package manager.")
endif()

option(USE_LUAJIT "Switch Lua/LuaJit (TRUE is highly recommended)" TRUE)
if(USE_LUAJIT)
    find_package(LuaJit QUIET)
    if(NOT LuaJit_FOUND)
        message(STATUS "LuaJit not found, falling back to regular Lua")
        set(USE_LUAJIT FALSE)
        find_package(Lua REQUIRED)
        add_compile_definitions(NO_LUAJIT)
    else()
        set(LUA_INCLUDE_DIR ${LuaJit_INCLUDE_DIR})
        set(LUA_LIBRARIES ${LuaJit_LIBRARIES})
    endif()
else(USE_LUAJIT)
    find_package(Lua REQUIRED)
    add_compile_definitions(NO_LUAJIT)
endif(USE_LUAJIT)
if (NOT WIN32 AND NOT ANDROID)
    include(cmake/CheckLuaCustomAllocator.cmake)
endif()

# C++ library binding to Lua
set(SOL_INCLUDE_DIR ${OpenMW_SOURCE_DIR}/extern/sol3)
set(SOL_CONFIG_DIR ${OpenMW_SOURCE_DIR}/extern/sol_config)

include_directories(
    BEFORE SYSTEM
    ${OPENAL_INCLUDE_DIR}
    ${OPENGL_INCLUDE_DIR}
    ${BULLET_INCLUDE_DIRS}
    ${LUA_INCLUDE_DIR}
    ${SOL_INCLUDE_DIR}
    ${SOL_CONFIG_DIR}
    ${ICU_INCLUDE_DIRS}
)
# Always add MyGUI include directories (for both system and internal builds)
if(MyGUI_INCLUDE_DIRS)
    include_directories(BEFORE SYSTEM ${MyGUI_INCLUDE_DIRS})
endif()
include_directories(".")

link_directories(${COLLADA_DOM_LIBRARY_DIRS})

if(MYGUI_STATIC)
    add_definitions(-DMYGUI_STATIC)
endif (MYGUI_STATIC)

if (APPLE)
    configure_file(${OpenMW_SOURCE_DIR}/files/mac/openmw-Info.plist.in
        "${APP_BUNDLE_DIR}/Contents/Info.plist")

    configure_file(${OpenMW_SOURCE_DIR}/files/mac/openmw.icns
        "${APP_BUNDLE_DIR}/Contents/Resources/OpenMW.icns" COPYONLY)
endif (APPLE)

if (NOT APPLE)  # this is modified for macOS use later in "apps/open[mw|cs]/CMakeLists.txt"
    set(OPENMW_RESOURCES_ROOT ${OpenMW_BINARY_DIR})
endif ()

add_subdirectory(files/)

# Specify build paths

if (APPLE)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${APP_BUNDLE_DIR}/Contents/MacOS")
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${APP_BUNDLE_DIR}/Contents/MacOS")

    if (OPENMW_OSX_DEPLOYMENT)
        SET(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
    endif()
else (APPLE)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${OpenMW_BINARY_DIR}")
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${OpenMW_BINARY_DIR}")
endif (APPLE)

# Other files

pack_resource_file(${OpenMW_SOURCE_DIR}/files/settings-default.cfg
    "${OpenMW_BINARY_DIR}" "defaults.bin")

configure_resource_file(${OpenMW_SOURCE_DIR}/files/openmw.appdata.xml
    "${OpenMW_BINARY_DIR}" "openmw.appdata.xml")

if (APPLE)
    configure_file(${OpenMW_SOURCE_DIR}/files/openmw.cfg
        "${OpenMW_BINARY_DIR}/openmw.cfg")
elseif (WIN32)
    configure_resource_file(${OpenMW_SOURCE_DIR}/files/openmw.cfg.local
        "${OpenMW_BINARY_DIR}" "openmw.cfg")
    configure_resource_file(${OpenMW_SOURCE_DIR}/files/openmw.cfg.local
        "${OpenMW_BINARY_DIR}" "openmw.cfg.install")
else ()
    configure_resource_file(${OpenMW_SOURCE_DIR}/files/openmw.cfg.local
        "${OpenMW_BINARY_DIR}" "openmw.cfg")
    configure_resource_file(${OpenMW_SOURCE_DIR}/files/openmw.cfg
        "${OpenMW_BINARY_DIR}" "openmw.cfg.install")
endif ()

pack_resource_file(${OpenMW_SOURCE_DIR}/files/openmw-cs.cfg
    "${OpenMW_BINARY_DIR}" "defaults-cs.bin")

# Needs the copy version because the configure version assumes the end of the file has been reached when a null character is reached and there are no CMake expressions to evaluate.
copy_resource_file(${OpenMW_SOURCE_DIR}/files/opencs/defaultfilters
    "${OpenMW_BINARY_DIR}" "resources/defaultfilters")

configure_resource_file(${OpenMW_SOURCE_DIR}/files/gamecontrollerdb.txt
    "${OpenMW_BINARY_DIR}" "gamecontrollerdb.txt")

if (NOT WIN32 AND NOT APPLE)
    configure_file(${OpenMW_SOURCE_DIR}/files/org.openmw.launcher.desktop
        "${OpenMW_BINARY_DIR}/org.openmw.launcher.desktop")
    configure_file(${OpenMW_SOURCE_DIR}/files/openmw.appdata.xml
        "${OpenMW_BINARY_DIR}/openmw.appdata.xml")
    configure_file(${OpenMW_SOURCE_DIR}/files/org.openmw.cs.desktop
        "${OpenMW_BINARY_DIR}/org.openmw.cs.desktop")
endif()

if(OPENMW_LTO_BUILD)
    include(CheckIPOSupported)
    check_ipo_supported(RESULT HAVE_IPO OUTPUT HAVE_IPO_OUTPUT)
    if(HAVE_IPO)
        message(STATUS "LTO enabled for Release configuration.")
        set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)
    else()
        message(WARNING "Requested option OPENMW_LTO_BUILD not supported by this compiler: ${HAVE_IPO_OUTPUT}")
        if(MSVC)
            message(STATUS "Note: Flags used to be set manually for this setting with MSVC. We now rely on CMake for this. Upgrade CMake to at least 3.13 to re-enable this setting.")
        endif()
    endif()
endif()

if (APPLE)
    # -stdlib flag is Clang-specific, not supported by GCC
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|AppleClang")
        if(OPENMW_MACOSX_10_5)
            # macOS 10.5: libc++ was introduced in 10.7, but Clang might require it
            # Try to detect if libc++ is available, otherwise fall back to libstdc++
            include(CheckCXXCompilerFlag)
            check_cxx_compiler_flag("-stdlib=libc++" HAS_LIBCXX)
            
            if(HAS_LIBCXX)
                message(STATUS "Using libc++ for macOS 10.5 (Clang compatibility)")
                set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")
                set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -stdlib=libc++")
            else()
                message(STATUS "libc++ not available, using libstdc++ for macOS 10.5")
                set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libstdc++")
                set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -stdlib=libstdc++")
            endif()
        else()
            # Modern macOS: use libc++ with Clang
            set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")
            set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -stdlib=libc++")
        endif()
    else()
        # GCC: uses libstdc++ by default, no -stdlib flag needed
        if(OPENMW_MACOSX_10_5)
            message(STATUS "Using GCC - libstdc++ is default (no -stdlib flag needed)")
        else()
            message(STATUS "Using GCC - libstdc++ is default (no -stdlib flag needed)")
        endif()
    endif()
endif()

# Extern

add_subdirectory (extern/osg-ffmpeg-videoplayer)
add_subdirectory (extern/oics)
add_subdirectory (extern/Base64)
if ((BUILD_OPENCS OR BUILD_OPENCS_TESTS) AND USE_QT)
    add_subdirectory (extern/osgQt)
endif()

if (CMAKE_CXX_COMPILER_ID STREQUAL "MSVC" OR CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
    add_compile_options("/W4")

    set(WARNINGS_DISABLE
        4100 # Unreferenced formal parameter (-Wunused-parameter)
        4127 # Conditional expression is constant
        4996 # Function was declared deprecated
        5054 # Deprecated operations between enumerations of different types caused by Qt headers
        )

    foreach(d ${WARNINGS_DISABLE})
        add_compile_options("/wd${d}")
    endforeach(d)

    if(OPENMW_MSVC_WERROR)
        add_compile_options("/WX")
    endif()
else ()
    add_compile_options("-Wall" "-Wextra" "-Wundef" "-Wextra-semi" "-Wno-unused-parameter" "-pedantic" "-Wno-long-long" "-Wnon-virtual-dtor" "-Wunused" "-Wshadow")

    if (CMAKE_CXX_COMPILER_ID STREQUAL Clang AND NOT APPLE)
        if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER 3.6 OR CMAKE_CXX_COMPILER_VERSION VERSION_EQUAL 3.6)
            add_compile_options("-Wno-potentially-evaluated-expression")
        endif ()
    endif()

    if (CMAKE_CXX_COMPILER_ID STREQUAL GNU)
        add_compile_options("-Wno-unused-but-set-parameter" "-Wduplicated-branches" "-Wduplicated-cond" "-Wlogical-op")
        # https://gcc.gnu.org/bugzilla/show_bug.cgi?id=105438
        add_compile_options("-Wno-array-bounds")
    endif()
endif ()

if (OPENMW_CXX_FLAGS)
    separate_arguments(OPENMW_CXX_FLAGS NATIVE_COMMAND "${OPENMW_CXX_FLAGS}")
    add_compile_options(${OPENMW_CXX_FLAGS})
endif()

# Components
add_subdirectory (components)

# Apps and tools
if (BUILD_OPENMW OR BUILD_OPENMW_TESTS)
    add_subdirectory( apps/openmw )
endif()

if (BUILD_BSATOOL)
    add_subdirectory( apps/bsatool )
endif()

if (BUILD_ESMTOOL)
    add_subdirectory( apps/esmtool )
endif()

if (BUILD_LAUNCHER)
    add_subdirectory( apps/launcher )
endif()

if (BUILD_MWINIIMPORTER)
    add_subdirectory( apps/mwiniimporter )
endif()

if (BUILD_ESSIMPORTER)
    add_subdirectory (apps/essimporter )
endif()

if (BUILD_OPENCS OR BUILD_OPENCS_TESTS)
    add_subdirectory (apps/opencs)
endif()

if (BUILD_WIZARD)
    add_subdirectory(apps/wizard)
endif()

if (BUILD_NIFTEST)
    add_subdirectory(apps/niftest)
endif()

if (BUILD_COMPONENTS_TESTS)
    add_subdirectory(apps/components_tests)
endif()

if (BUILD_BENCHMARKS)
    add_subdirectory(apps/benchmarks)
endif()

if (BUILD_NAVMESHTOOL)
    add_subdirectory(apps/navmeshtool)
endif()

if (BUILD_BULLETOBJECTTOOL)
    add_subdirectory(apps/bulletobjecttool)
endif()

if (BUILD_OPENCS_TESTS)
    add_subdirectory(apps/opencs_tests)
endif()

if (BUILD_OPENMW_TESTS)
    add_subdirectory(apps/openmw_tests)
endif()

if (WIN32)
    if (MSVC)
        foreach( OUTPUTCONFIG ${CMAKE_CONFIGURATION_TYPES} )
            string( TOUPPER ${OUTPUTCONFIG} OUTPUTCONFIG )
            set( CMAKE_RUNTIME_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "$(SolutionDir)$(Configuration)" )
            set( CMAKE_LIBRARY_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "$(ProjectDir)$(Configuration)" )
        endforeach( OUTPUTCONFIG )

        if (USE_DEBUG_CONSOLE AND BUILD_OPENMW)
            set_target_properties(openmw PROPERTIES LINK_FLAGS_DEBUG "/SUBSYSTEM:CONSOLE")
            set_target_properties(openmw PROPERTIES LINK_FLAGS_RELWITHDEBINFO "/SUBSYSTEM:CONSOLE")
        elseif (BUILD_OPENMW)
            # Turn off implicit console, you won't see stdout unless launching OpenMW from a command line shell or look at openmw.log
            set_target_properties(openmw PROPERTIES LINK_FLAGS_DEBUG "/SUBSYSTEM:WINDOWS")
            set_target_properties(openmw PROPERTIES LINK_FLAGS_RELWITHDEBINFO "/SUBSYSTEM:WINDOWS")
        endif()

        if (BUILD_OPENMW)
            # Release builds don't use the debug console
            set_target_properties(openmw PROPERTIES LINK_FLAGS_RELEASE "/SUBSYSTEM:WINDOWS")
            set_target_properties(openmw PROPERTIES LINK_FLAGS_MINSIZEREL "/SUBSYSTEM:WINDOWS")
        endif()

        if (MSVC_VERSION GREATER_EQUAL 1915 AND MSVC_VERSION LESS 1920)
            target_compile_definitions(components INTERFACE _ENABLE_EXTENDED_ALIGNED_STORAGE)
        endif()
    endif(MSVC)

    # TODO: At some point release builds should not use the console but rather write to a log file
    #set_target_properties(openmw PROPERTIES LINK_FLAGS_RELEASE "/SUBSYSTEM:WINDOWS")
    #set_target_properties(openmw PROPERTIES LINK_FLAGS_MINSIZEREL "/SUBSYSTEM:WINDOWS")
endif()

# Apple bundling
if (OPENMW_OSX_DEPLOYMENT AND APPLE)
    if (CMAKE_VERSION VERSION_LESS 3.19)
        message(FATAL_ERROR "macOS packaging requires CMake 3.19 or higher to sign macOS app bundles.")
    endif ()

    if (USE_QT)
        get_property(QT_COCOA_PLUGIN_PATH TARGET Qt${QT_VERSION_MAJOR}::QCocoaIntegrationPlugin PROPERTY LOCATION_RELEASE)
        get_filename_component(QT_COCOA_PLUGIN_DIR "${QT_COCOA_PLUGIN_PATH}" DIRECTORY)
        get_filename_component(QT_COCOA_PLUGIN_GROUP "${QT_COCOA_PLUGIN_DIR}" NAME)
        get_filename_component(QT_COCOA_PLUGIN_NAME "${QT_COCOA_PLUGIN_PATH}" NAME)
        configure_file("${QT_COCOA_PLUGIN_PATH}" "${APP_BUNDLE_DIR}/Contents/PlugIns/${QT_COCOA_PLUGIN_GROUP}/${QT_COCOA_PLUGIN_NAME}" COPYONLY)

        get_property(QT_QMACSTYLE_PLUGIN_PATH TARGET Qt${QT_VERSION_MAJOR}::QMacStylePlugin PROPERTY LOCATION_RELEASE)
        get_filename_component(QT_QMACSTYLE_PLUGIN_DIR "${QT_QMACSTYLE_PLUGIN_PATH}" DIRECTORY)
        get_filename_component(QT_QMACSTYLE_PLUGIN_GROUP "${QT_QMACSTYLE_PLUGIN_DIR}" NAME)
        get_filename_component(QT_QMACSTYLE_PLUGIN_NAME "${QT_QMACSTYLE_PLUGIN_PATH}" NAME)
        configure_file("${QT_QMACSTYLE_PLUGIN_PATH}" "${APP_BUNDLE_DIR}/Contents/PlugIns/${QT_QMACSTYLE_PLUGIN_GROUP}/${QT_QMACSTYLE_PLUGIN_NAME}" COPYONLY)

        get_property(QT_QSVG_PLUGIN_PATH TARGET Qt${QT_VERSION_MAJOR}::QSvgPlugin PROPERTY LOCATION_RELEASE)
        get_filename_component(QT_QSVG_PLUGIN_DIR "${QT_QSVG_PLUGIN_PATH}" DIRECTORY)
        get_filename_component(QT_QSVG_PLUGIN_GROUP "${QT_QSVG_PLUGIN_DIR}" NAME)
        get_filename_component(QT_QSVG_PLUGIN_NAME "${QT_QSVG_PLUGIN_PATH}" NAME)
        configure_file("${QT_QSVG_PLUGIN_PATH}" "${APP_BUNDLE_DIR}/Contents/PlugIns/${QT_QSVG_PLUGIN_GROUP}/${QT_QSVG_PLUGIN_NAME}" COPYONLY)

        get_property(QT_QSVG_ICON_PLUGIN_PATH TARGET Qt${QT_VERSION_MAJOR}::QSvgIconPlugin PROPERTY LOCATION_RELEASE)
        get_filename_component(QT_QSVG_ICON_PLUGIN_DIR "${QT_QSVG_ICON_PLUGIN_PATH}" DIRECTORY)
        get_filename_component(QT_QSVG_ICON_PLUGIN_GROUP "${QT_QSVG_ICON_PLUGIN_DIR}" NAME)
        get_filename_component(QT_QSVG_ICON_PLUGIN_NAME "${QT_QSVG_ICON_PLUGIN_PATH}" NAME)
        configure_file("${QT_QSVG_ICON_PLUGIN_PATH}" "${APP_BUNDLE_DIR}/Contents/PlugIns/${QT_QSVG_ICON_PLUGIN_GROUP}/${QT_QSVG_ICON_PLUGIN_NAME}" COPYONLY)

        configure_file("${OpenMW_SOURCE_DIR}/files/mac/qt.conf" "${APP_BUNDLE_DIR}/Contents/Resources/qt.conf" COPYONLY)

        if (BUILD_OPENCS)
            get_property(OPENCS_BUNDLE_NAME_TMP TARGET openmw-cs PROPERTY OUTPUT_NAME)
            set(OPENCS_BUNDLE_NAME "${OPENCS_BUNDLE_NAME_TMP}.app")
            configure_file("${QT_COCOA_PLUGIN_PATH}" "${OPENCS_BUNDLE_NAME}/Contents/PlugIns/${QT_COCOA_PLUGIN_GROUP}/${QT_COCOA_PLUGIN_NAME}" COPYONLY)
            configure_file("${QT_QMACSTYLE_PLUGIN_PATH}" "${OPENCS_BUNDLE_NAME}/Contents/PlugIns/${QT_QMACSTYLE_PLUGIN_GROUP}/${QT_QMACSTYLE_PLUGIN_NAME}" COPYONLY)
            configure_file("${QT_QSVG_PLUGIN_PATH}" "${OPENCS_BUNDLE_NAME}/Contents/PlugIns/${QT_QSVG_PLUGIN_GROUP}/${QT_QSVG_PLUGIN_NAME}" COPYONLY)
            configure_file("${QT_QSVG_ICON_PLUGIN_PATH}" "${OPENCS_BUNDLE_NAME}/Contents/PlugIns/${QT_QSVG_ICON_PLUGIN_GROUP}/${QT_QSVG_ICON_PLUGIN_NAME}" COPYONLY)
            configure_file("${OpenMW_SOURCE_DIR}/files/mac/qt.conf" "${OPENCS_BUNDLE_NAME}/Contents/Resources/qt.conf" COPYONLY)
        endif ()
    endif()

    install(DIRECTORY "${APP_BUNDLE_DIR}" USE_SOURCE_PERMISSIONS DESTINATION "." COMPONENT Runtime)

    set(CPACK_GENERATOR "DragNDrop")
    set(CPACK_PACKAGE_VERSION ${OPENMW_VERSION})
    set(CPACK_PACKAGE_VERSION_MAJOR ${OPENMW_VERSION_MAJOR})
    set(CPACK_PACKAGE_VERSION_MINOR ${OPENMW_VERSION_MINOR})
    set(CPACK_PACKAGE_VERSION_PATCH ${OPENMW_VERSION_RELEASE})

    set(INSTALLED_OPENMW_APP "\${CMAKE_INSTALL_PREFIX}/${APP_BUNDLE_NAME}")
    set(INSTALLED_OPENCS_APP "\${CMAKE_INSTALL_PREFIX}/${OPENCS_BUNDLE_NAME}")

    install(CODE "
        set(BU_CHMOD_BUNDLE_ITEMS ON)
        set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH})
        include(BundleUtilities)
    " COMPONENT Runtime)

    set(ABSOLUTE_PLUGINS "")

    set(OSGPlugins_DONT_FIND_DEPENDENCIES 1)
    if(OPENMW_USE_SYSTEM_OSG)
        find_package(OSGPlugins QUIET COMPONENTS ${USED_OSG_PLUGINS})
        if(NOT OSGPlugins_FOUND)
            message(WARNING "System OSGPlugins not found for macOS deployment. Plugins will be copied from internal build.")
            # For internal build, plugins will be in the OSG build directory
            # We'll need to construct paths manually or skip this section
        endif()
    else()
        # OSGPlugins will be available from internal OSG build
        message(STATUS "Using OSGPlugins from internal OSG build")
        # For internal builds, we need to find plugins in the build directory
        # This will be handled by the OSG build system
    endif()
    
    # If OSGPlugins not found, we'll try to continue anyway (plugins may be in internal build)
    if(NOT OSGPlugins_FOUND AND OPENMW_USE_SYSTEM_OSG)
        message(WARNING "OSGPlugins not found - deployment may be incomplete. Consider using internal OSG build.")
    endif()

    foreach (PLUGIN_NAME ${USED_OSG_PLUGINS})
        string(TOUPPER ${PLUGIN_NAME} PLUGIN_NAME_UC)
        set(PLUGIN_ABS "")
        if(OPENMW_USE_SYSTEM_OSG)
            if(${PLUGIN_NAME_UC}_LIBRARY_RELEASE)
                set(PLUGIN_ABS ${${PLUGIN_NAME_UC}_LIBRARY_RELEASE})
            elseif(${PLUGIN_NAME_UC}_LIBRARY)
                set(PLUGIN_ABS ${${PLUGIN_NAME_UC}_LIBRARY})
            endif()
        else()
            # For internal OSG build, check if target exists and get its file path
            set(_plugin_target ${${PLUGIN_NAME_UC}_LIBRARY})
            if(TARGET ${_plugin_target})
                set(PLUGIN_ABS $<TARGET_FILE:${_plugin_target}>)
            endif()
        endif()
        if(PLUGIN_ABS)
            set(ABSOLUTE_PLUGINS ${PLUGIN_ABS} ${ABSOLUTE_PLUGINS})
        else()
            message(WARNING "OSG plugin ${PLUGIN_NAME} not found - skipping for macOS deployment")
            message(WARNING "  Plugin may be disabled due to missing dependencies")
        endif()
    endforeach ()

    set(OSG_PLUGIN_PREFIX_DIR "osgPlugins-${OPENSCENEGRAPH_VERSION}")

    # installs used plugins in bundle at given path (bundle_path must be relative to ${CMAKE_INSTALL_PREFIX})
    # and returns list of install paths for all installed plugins
    function (install_plugins_for_bundle bundle_path plugins_var)
        set(RELATIVE_PLUGIN_INSTALL_BASE "${bundle_path}/Contents/PlugIns/${OSG_PLUGIN_PREFIX_DIR}")

        set(PLUGINS "")
        set(PLUGIN_INSTALL_BASE "\${CMAKE_INSTALL_PREFIX}/${RELATIVE_PLUGIN_INSTALL_BASE}")

        foreach (PLUGIN ${ABSOLUTE_PLUGINS})
            get_filename_component(PLUGIN_RELATIVE ${PLUGIN} NAME)
            get_filename_component(PLUGIN_RELATIVE_WE ${PLUGIN} NAME_WE)

            set(PLUGIN_DYLIB_IN_BUNDLE "${PLUGIN_INSTALL_BASE}/${PLUGIN_RELATIVE}")
            set(PLUGINS ${PLUGINS} "${PLUGIN_DYLIB_IN_BUNDLE}")

            install(CODE "
                copy_resolved_item_into_bundle(\"${PLUGIN}\" \"${PLUGIN_DYLIB_IN_BUNDLE}\")
            " COMPONENT Runtime)
        endforeach ()

        set(${plugins_var} ${PLUGINS} PARENT_SCOPE)
    endfunction (install_plugins_for_bundle)

    install_plugins_for_bundle("${APP_BUNDLE_NAME}" PLUGINS)
    install_plugins_for_bundle("${OPENCS_BUNDLE_NAME}" OPENCS_PLUGINS)

    INSTALL(FILES "${OpenMW_SOURCE_DIR}/CHANGELOG.md" DESTINATION "/${INSTALLED_OPENMW_APP}/..")
    INSTALL(FILES "${OpenMW_SOURCE_DIR}/README.md" DESTINATION "/${INSTALLED_OPENMW_APP}/..")
    INSTALL(FILES "${OpenMW_SOURCE_DIR}/LICENSE" DESTINATION "/${INSTALLED_OPENMW_APP}/..")
    INSTALL(FILES "${OpenMW_SOURCE_DIR}/AUTHORS.md" DESTINATION "/${INSTALLED_OPENMW_APP}/..")

    if (USE_QT)
        set(PLUGINS ${PLUGINS} "${INSTALLED_OPENMW_APP}/Contents/PlugIns/${QT_COCOA_PLUGIN_GROUP}/${QT_COCOA_PLUGIN_NAME}")
        set(PLUGINS ${PLUGINS} "${INSTALLED_OPENMW_APP}/Contents/PlugIns/${QT_QMACSTYLE_PLUGIN_GROUP}/${QT_QMACSTYLE_PLUGIN_NAME}")
        set(OPENCS_PLUGINS ${OPENCS_PLUGINS} "${INSTALLED_OPENCS_APP}/Contents/PlugIns/${QT_COCOA_PLUGIN_GROUP}/${QT_COCOA_PLUGIN_NAME}")
        set(OPENCS_PLUGINS ${OPENCS_PLUGINS} "${INSTALLED_OPENCS_APP}/Contents/PlugIns/${QT_QMACSTYLE_PLUGIN_GROUP}/${QT_QMACSTYLE_PLUGIN_NAME}")
    endif()

    install(CODE "
        function(gp_item_default_embedded_path_override item  default_embedded_path_var)
            if (\${item} MATCHES ${OSG_PLUGIN_PREFIX_DIR})
              set(path \"@executable_path/../PlugIns/${OSG_PLUGIN_PREFIX_DIR}\")
              set(\${default_embedded_path_var} \"\${path}\" PARENT_SCOPE)
            endif()
        endfunction()

        fixup_bundle(\"${INSTALLED_OPENMW_APP}\" \"${PLUGINS}\" \"\")
        fixup_bundle(\"${INSTALLED_OPENCS_APP}\" \"${OPENCS_PLUGINS}\" \"\")
        " COMPONENT Runtime)

    set(CPACK_PRE_BUILD_SCRIPTS ${CMAKE_SOURCE_DIR}/cmake/SignMacApplications.cmake)

    include(CPack)
elseif(NOT APPLE)
    get_generator_is_multi_config(multi_config)
    if (multi_config)
        SET(INSTALL_SOURCE "${OpenMW_BINARY_DIR}/$<CONFIG>")
    else ()
        SET(INSTALL_SOURCE "${OpenMW_BINARY_DIR}")
    endif ()

    if(WIN32)
        INSTALL(DIRECTORY "${INSTALL_SOURCE}/" DESTINATION "." FILES_MATCHING PATTERN "*.dll"
                                                                              PATTERN ".cmake" EXCLUDE
                                                                              PATTERN ".qt" EXCLUDE
                                                                              PATTERN "_CPack_Packages" EXCLUDE
                                                                              PATTERN "_deps" EXCLUDE
                                                                              PATTERN "apps" EXCLUDE
                                                                              PATTERN "bin" EXCLUDE
                                                                              PATTERN "CMakeFiles" EXCLUDE
                                                                              PATTERN "components" EXCLUDE
                                                                              PATTERN "deps" EXCLUDE
                                                                              PATTERN "docs" EXCLUDE
                                                                              PATTERN "extern" EXCLUDE
                                                                              PATTERN "files" EXCLUDE
                                                                              PATTERN "lib" EXCLUDE
                                                                              PATTERN "SymStore" EXCLUDE
                                                                              PATTERN "symstore-venv" EXCLUDE
                                                                              PATTERN "Testing" EXCLUDE
                                                                              PATTERN "tests_output" EXCLUDE
                                                                              PATTERN "try-compile")
        INSTALL(DIRECTORY "${INSTALL_SOURCE}/" DESTINATION "." CONFIGURATIONS Debug;RelWithDebInfo FILES_MATCHING PATTERN "*.pdb"
                                                                                                                  PATTERN ".cmake" EXCLUDE
                                                                                                                  PATTERN ".qt" EXCLUDE
                                                                                                                  PATTERN "_CPack_Packages" EXCLUDE
                                                                                                                  PATTERN "_deps" EXCLUDE
                                                                                                                  PATTERN "apps" EXCLUDE
                                                                                                                  PATTERN "bin" EXCLUDE
                                                                                                                  PATTERN "CMakeFiles" EXCLUDE
                                                                                                                  PATTERN "components" EXCLUDE
                                                                                                                  PATTERN "deps" EXCLUDE
                                                                                                                  PATTERN "docs" EXCLUDE
                                                                                                                  PATTERN "extern" EXCLUDE
                                                                                                                  PATTERN "files" EXCLUDE
                                                                                                                  PATTERN "lib" EXCLUDE
                                                                                                                  PATTERN "SymStore" EXCLUDE
                                                                                                                  PATTERN "symstore-venv" EXCLUDE
                                                                                                                  PATTERN "Testing" EXCLUDE
                                                                                                                  PATTERN "tests_output" EXCLUDE
                                                                                                                  PATTERN "try-compile")
        INSTALL(FILES "${INSTALL_SOURCE}/openmw.cfg.install" DESTINATION "." RENAME "openmw.cfg")
        INSTALL(FILES "${OpenMW_SOURCE_DIR}/CHANGELOG.md" DESTINATION "." RENAME "CHANGELOG.txt")
        INSTALL(FILES "${OpenMW_SOURCE_DIR}/README.md" DESTINATION "." RENAME "README.txt")
        INSTALL(FILES "${OpenMW_SOURCE_DIR}/LICENSE" DESTINATION "." RENAME "LICENSE.txt")
        INSTALL(FILES "${OpenMW_SOURCE_DIR}/AUTHORS.md" DESTINATION "." RENAME "AUTHORS.txt")
        INSTALL(FILES "${INSTALL_SOURCE}/defaults.bin" DESTINATION ".")
        INSTALL(FILES "${INSTALL_SOURCE}/gamecontrollerdb.txt" DESTINATION ".")

        INSTALL(DIRECTORY "${INSTALL_SOURCE}/resources" DESTINATION ".")

        SET(CPACK_GENERATOR "NSIS")
        SET(CPACK_PACKAGE_NAME "OpenMW")
        SET(CPACK_PACKAGE_VENDOR "OpenMW.org")
        SET(CPACK_PACKAGE_VERSION ${OPENMW_VERSION})
        SET(CPACK_PACKAGE_VERSION_MAJOR ${OPENMW_VERSION_MAJOR})
        SET(CPACK_PACKAGE_VERSION_MINOR ${OPENMW_VERSION_MINOR})
        SET(CPACK_PACKAGE_VERSION_PATCH ${OPENMW_VERSION_RELEASE})
        SET(CPACK_PACKAGE_EXECUTABLES "openmw;OpenMW")
        IF(BUILD_LAUNCHER)
            SET(CPACK_PACKAGE_EXECUTABLES "${CPACK_PACKAGE_EXECUTABLES};openmw-launcher;OpenMW Launcher")
        ENDIF(BUILD_LAUNCHER)
        IF(BUILD_OPENCS)
            SET(CPACK_PACKAGE_EXECUTABLES "${CPACK_PACKAGE_EXECUTABLES};openmw-cs;OpenMW Construction Set")
        ENDIF(BUILD_OPENCS)
        IF(BUILD_WIZARD)
            SET(CPACK_PACKAGE_EXECUTABLES "${CPACK_PACKAGE_EXECUTABLES};openmw-wizard;OpenMW Wizard")
        ENDIF(BUILD_WIZARD)
        SET(CPACK_NSIS_CREATE_ICONS_EXTRA "CreateShortCut '\$SMPROGRAMS\\\\$STARTMENU_FOLDER\\\\Readme.lnk' '\$INSTDIR\\\\README.txt'")
        SET(CPACK_NSIS_DELETE_ICONS_EXTRA "
            !insertmacro MUI_STARTMENU_GETFOLDER Application $MUI_TEMP
            Delete \\\"$SMPROGRAMS\\\\$MUI_TEMP\\\\Readme.lnk\\\"
            ")
        SET(CPACK_RESOURCE_FILE_README "${OpenMW_SOURCE_DIR}/README.md")
        SET(CPACK_PACKAGE_DESCRIPTION_FILE "${OpenMW_SOURCE_DIR}/README.md")
        SET(CPACK_NSIS_EXECUTABLES_DIRECTORY ".")
        SET(CPACK_NSIS_DISPLAY_NAME "OpenMW ${OPENMW_VERSION}")
        SET(CPACK_NSIS_HELP_LINK "https:\\\\\\\\www.openmw.org")
        SET(CPACK_NSIS_URL_INFO_ABOUT "https:\\\\\\\\www.openmw.org")
        SET(CPACK_NSIS_INSTALLED_ICON_NAME "openmw-launcher.exe")
        SET(CPACK_NSIS_MUI_FINISHPAGE_RUN "openmw-launcher.exe")
        SET(CPACK_NSIS_MUI_ICON "${OpenMW_SOURCE_DIR}/files/windows/openmw.ico")
        SET(CPACK_NSIS_MUI_UNIICON "${OpenMW_SOURCE_DIR}/files/windows/openmw.ico")
        SET(CPACK_PACKAGE_ICON "${OpenMW_SOURCE_DIR}\\\\files\\\\openmw.bmp")

        SET(VCREDIST64 "${OpenMW_BINARY_DIR}/vcredist_x64.exe" CACHE FILEPATH "Path to vcredist_x64.exe")
        if(EXISTS ${VCREDIST64})
            INSTALL(FILES ${VCREDIST64} DESTINATION "redist")
            get_filename_component(REDIST_FILENAME "${VCREDIST64}" NAME)
            SET(CPACK_NSIS_EXTRA_INSTALL_COMMANDS "
                ExecWait '\\\"$INSTDIR\\\\redist\\\\${REDIST_FILENAME}\\\" /q /norestart'
                RMDir /r \\\"$INSTDIR\\\\redist\\\"
                ")
        endif(EXISTS ${VCREDIST64})

        if(CMAKE_CL_64)
            SET(CPACK_NSIS_INSTALL_ROOT "$PROGRAMFILES64")
        endif()

        include(CPack)
    else(WIN32)
        # Linux installation

        # Install binaries
        IF(BUILD_OPENMW)
            INSTALL(PROGRAMS "$<TARGET_FILE:openmw>" DESTINATION "${BINDIR}" )
        ENDIF(BUILD_OPENMW)
        IF(BUILD_LAUNCHER)
            INSTALL(PROGRAMS "${INSTALL_SOURCE}/openmw-launcher" DESTINATION "${BINDIR}" )
        ENDIF(BUILD_LAUNCHER)
        IF(BUILD_BSATOOL)
            INSTALL(PROGRAMS "${INSTALL_SOURCE}/bsatool" DESTINATION "${BINDIR}" )
        ENDIF(BUILD_BSATOOL)
        IF(BUILD_ESMTOOL)
            INSTALL(PROGRAMS "${INSTALL_SOURCE}/esmtool" DESTINATION "${BINDIR}" )
        ENDIF(BUILD_ESMTOOL)
        IF(BUILD_NIFTEST)
            INSTALL(PROGRAMS "${INSTALL_SOURCE}/niftest" DESTINATION "${BINDIR}" )
        ENDIF(BUILD_NIFTEST)
        IF(BUILD_MWINIIMPORTER)
            INSTALL(PROGRAMS "${INSTALL_SOURCE}/openmw-iniimporter" DESTINATION "${BINDIR}" )
        ENDIF(BUILD_MWINIIMPORTER)
        IF(BUILD_ESSIMPORTER)
            INSTALL(PROGRAMS "${INSTALL_SOURCE}/openmw-essimporter" DESTINATION "${BINDIR}" )
        ENDIF(BUILD_ESSIMPORTER)
        IF(BUILD_OPENCS)
            INSTALL(PROGRAMS "${INSTALL_SOURCE}/openmw-cs" DESTINATION "${BINDIR}" )
        ENDIF(BUILD_OPENCS)
        IF(BUILD_WIZARD)
            INSTALL(PROGRAMS "${INSTALL_SOURCE}/openmw-wizard" DESTINATION "${BINDIR}" )
        ENDIF(BUILD_WIZARD)
        if(BUILD_NAVMESHTOOL)
            install(PROGRAMS "${INSTALL_SOURCE}/openmw-navmeshtool" DESTINATION "${BINDIR}" )
        endif()
        IF(BUILD_BULLETOBJECTTOOL)
            INSTALL(PROGRAMS "${INSTALL_SOURCE}/openmw-bulletobjecttool" DESTINATION "${BINDIR}" )
        ENDIF(BUILD_BULLETOBJECTTOOL)

        # Install icon and desktop file
        INSTALL(FILES "${OpenMW_BINARY_DIR}/org.openmw.launcher.desktop" DESTINATION "${DATAROOTDIR}/applications" COMPONENT "openmw")
        INSTALL(FILES "${OpenMW_SOURCE_DIR}/files/launcher/images/openmw.png" DESTINATION "${ICONDIR}" COMPONENT "openmw")
        INSTALL(FILES "${OpenMW_BINARY_DIR}/openmw.appdata.xml" DESTINATION "${DATAROOTDIR}/metainfo" COMPONENT "openmw")
        IF(BUILD_OPENCS)
            INSTALL(FILES "${OpenMW_BINARY_DIR}/org.openmw.cs.desktop" DESTINATION "${DATAROOTDIR}/applications" COMPONENT "opencs")
            INSTALL(FILES "${OpenMW_SOURCE_DIR}/files/opencs/openmw-cs.png" DESTINATION "${ICONDIR}" COMPONENT "opencs")
        ENDIF(BUILD_OPENCS)

        # Install global configuration files
        INSTALL(FILES "${INSTALL_SOURCE}/defaults.bin" DESTINATION "${SYSCONFDIR}" COMPONENT "openmw")
        INSTALL(FILES "${INSTALL_SOURCE}/openmw.cfg.install" DESTINATION "${SYSCONFDIR}" RENAME "openmw.cfg" COMPONENT "openmw")
        INSTALL(FILES "${INSTALL_SOURCE}/gamecontrollerdb.txt" DESTINATION "${SYSCONFDIR}" COMPONENT "openmw")

        IF(BUILD_OPENCS)
            INSTALL(FILES "${INSTALL_SOURCE}/defaults-cs.bin" DESTINATION "${SYSCONFDIR}" COMPONENT "opencs")
        ENDIF(BUILD_OPENCS)

        # Install resources
        INSTALL(DIRECTORY "${INSTALL_SOURCE}/resources" DESTINATION "${DATADIR}" COMPONENT "Resources")
    endif(WIN32)
endif(OPENMW_OSX_DEPLOYMENT AND APPLE)

# what is necessary to build documentation
if ( BUILD_DOCS )
    # Builds the documentation.
    FIND_PACKAGE( Sphinx REQUIRED )
    FIND_PACKAGE( Doxygen REQUIRED )

    # Doxygen Target -- simply run 'make doc' or 'make doc_pages'
    # output directory for 'make doc'       is "${OpenMW_BINARY_DIR}/docs/Doxygen"
    # output directory for 'make doc_pages' is "${DOXYGEN_PAGES_OUTPUT_DIR}" if defined
    #                                       or "${OpenMW_BINARY_DIR}/docs/Pages" otherwise

    # determine output directory for doc_pages
    if (NOT DEFINED DOXYGEN_PAGES_OUTPUT_DIR)
        set(DOXYGEN_PAGES_OUTPUT_DIR "${OpenMW_BINARY_DIR}/docs/Pages")
    endif ()
    configure_file(${OpenMW_SOURCE_DIR}/docs/Doxyfile.cmake ${OpenMW_BINARY_DIR}/docs/Doxyfile @ONLY)
    configure_file(${OpenMW_SOURCE_DIR}/docs/DoxyfilePages.cmake ${OpenMW_BINARY_DIR}/docs/DoxyfilePages @ONLY)
    add_custom_target(doc
        ${DOXYGEN_EXECUTABLE} ${OpenMW_BINARY_DIR}/docs/Doxyfile
        WORKING_DIRECTORY ${OpenMW_BINARY_DIR}
        COMMENT "Generating Doxygen documentation at ${OpenMW_BINARY_DIR}/docs/Doxygen"
        VERBATIM)
    add_custom_target(doc_pages
        ${DOXYGEN_EXECUTABLE} ${OpenMW_BINARY_DIR}/docs/DoxyfilePages
        WORKING_DIRECTORY ${OpenMW_BINARY_DIR}
        COMMENT "Generating documentation for the github-pages at ${DOXYGEN_PAGES_OUTPUT_DIR}" VERBATIM)
endif ()

# Qt localization
if (USE_QT)
    file(GLOB LAUNCHER_TS_FILES ${CMAKE_SOURCE_DIR}/files/lang/launcher_*.ts)
    file(GLOB WIZARD_TS_FILES ${CMAKE_SOURCE_DIR}/files/lang/wizard_*.ts)
    file(GLOB COMPONENTS_TS_FILES ${CMAKE_SOURCE_DIR}/files/lang/components_*.ts)
    if(USE_QT4)
        # For Qt4, find lupdate manually
        find_program(QT_LUPDATE_EXECUTABLE lupdate PATHS ${QT_BINARY_DIR} NO_DEFAULT_PATH)
        if(NOT QT_LUPDATE_EXECUTABLE)
            find_program(QT_LUPDATE_EXECUTABLE lupdate)
        endif()
        if(NOT QT_LUPDATE_EXECUTABLE)
            message(WARNING "lupdate not found - translation updates will not work")
        endif()
    else()
        get_target_property(QT_LUPDATE_EXECUTABLE Qt::lupdate IMPORTED_LOCATION)
        if(NOT QT_LUPDATE_EXECUTABLE)
            message(WARNING "Qt::lupdate target not found - translation updates may not work")
        endif()
    endif()
    
    if(QT_LUPDATE_EXECUTABLE)
        add_custom_target(translations
        COMMAND ${QT_LUPDATE_EXECUTABLE} -locations none ${CMAKE_SOURCE_DIR}/components/contentselector ${CMAKE_SOURCE_DIR}/components/process -ts ${COMPONENTS_TS_FILES}
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/components
        VERBATIM
        COMMAND_EXPAND_LISTS

        COMMAND ${QT_LUPDATE_EXECUTABLE} -locations none ${CMAKE_SOURCE_DIR}/apps/wizard -ts ${WIZARD_TS_FILES}
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/apps/wizard
        VERBATIM
        COMMAND_EXPAND_LISTS

        COMMAND ${QT_LUPDATE_EXECUTABLE} -locations none ${CMAKE_SOURCE_DIR}/apps/launcher -ts ${LAUNCHER_TS_FILES}
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/apps/launcher
        VERBATIM
        COMMAND_EXPAND_LISTS)
    else()
        # Create a dummy target if lupdate is not available
        add_custom_target(translations
        COMMENT "lupdate not found, skipping translation updates"
        VERBATIM)
    endif()

    if (BUILD_LAUNCHER OR BUILD_WIZARD)
        if (APPLE)
            set(QT_OPENMW_TRANSLATIONS_PATH "${APP_BUNDLE_DIR}/Contents/Resources/resources/translations")
        else ()
            get_generator_is_multi_config(multi_config)
            if (multi_config)
                set(QT_OPENMW_TRANSLATIONS_PATH "${OpenMW_BINARY_DIR}/$<CONFIG>/resources/translations")
            else ()
                set(QT_OPENMW_TRANSLATIONS_PATH "${OpenMW_BINARY_DIR}/resources/translations")
            endif ()
        endif ()

        file(GLOB TS_FILES ${COMPONENTS_TS_FILES})

        if (BUILD_LAUNCHER)
            set(TS_FILES ${TS_FILES} ${LAUNCHER_TS_FILES})
        endif ()

        if (BUILD_WIZARD)
            set(TS_FILES ${TS_FILES} ${WIZARD_TS_FILES})
        endif ()

        if(USE_QT4)
            # For Qt4, use lrelease instead of qt_add_translation
            find_program(QT_LRELEASE_EXECUTABLE lrelease PATHS ${QT_BINARY_DIR} NO_DEFAULT_PATH)
            if(NOT QT_LRELEASE_EXECUTABLE)
                find_program(QT_LRELEASE_EXECUTABLE lrelease)
            endif()
            if(QT_LRELEASE_EXECUTABLE)
                set(QM_FILES "")
                foreach(TS_FILE ${TS_FILES})
                    get_filename_component(TS_BASENAME ${TS_FILE} NAME_WE)
                    set(QM_FILE "${CMAKE_CURRENT_BINARY_DIR}/${TS_BASENAME}.qm")
                    add_custom_command(OUTPUT ${QM_FILE}
                        COMMAND ${QT_LRELEASE_EXECUTABLE} -silent ${TS_FILE} -qm ${QM_FILE}
                        DEPENDS ${TS_FILE}
                        COMMENT "Generating ${TS_BASENAME}.qm")
                    list(APPEND QM_FILES ${QM_FILE})
                endforeach()
            else()
                message(WARNING "lrelease not found - translation files will not be generated")
                set(QM_FILES "")
            endif()
        else()
            qt_add_translation(QM_FILES ${TS_FILES} OPTIONS -silent)
        endif()

        if (DEPLOY_QT_TRANSLATIONS)
            if(USE_QT4)
                # For Qt4, use qmake to query translations directory
                if(QT_QMAKE_EXECUTABLE)
                    execute_process(COMMAND "${QT_QMAKE_EXECUTABLE}" -query QT_INSTALL_TRANSLATIONS
                        OUTPUT_VARIABLE QT_TRANSLATIONS_DIR OUTPUT_STRIP_TRAILING_WHITESPACE)
                else()
                    message(WARNING "qmake not found - Qt translations deployment disabled")
                    set(DEPLOY_QT_TRANSLATIONS OFF)
                endif()
            else()
                # Once we set a Qt 6.2.0 as a minimum required version, we may use "qtpaths --qt-query" instead.
                get_target_property(QT_QMAKE_EXECUTABLE Qt::qmake IMPORTED_LOCATION)
                execute_process(COMMAND "${QT_QMAKE_EXECUTABLE}" -query QT_INSTALL_TRANSLATIONS
                    OUTPUT_VARIABLE QT_TRANSLATIONS_DIR OUTPUT_STRIP_TRAILING_WHITESPACE)
            endif()

            foreach(QM_FILE ${QM_FILES})
                get_filename_component(QM_BASENAME ${QM_FILE} NAME)
                string(REGEX REPLACE "[^_]+_(.*)\\.qm" "\\1" LANG_NAME ${QM_BASENAME})
                if (EXISTS "${QT_TRANSLATIONS_DIR}/qtbase_${LANG_NAME}.qm")
                    set(QM_FILES ${QM_FILES} "${QT_TRANSLATIONS_DIR}/qtbase_${LANG_NAME}.qm")
                elseif (EXISTS "${QT_TRANSLATIONS_DIR}/qt_${LANG_NAME}.qm")
                    set(QM_FILES ${QM_FILES} "${QT_TRANSLATIONS_DIR}/qt_${LANG_NAME}.qm")
                else ()
                    if(OPENMW_MACOSX_10_5)
                        message(WARNING "Qt translations for '${LANG_NAME}' locale are not found in the '${QT_TRANSLATIONS_DIR}' folder. Continuing without Qt translations.")
                    else()
                        message(FATAL_ERROR "Qt translations for '${LANG_NAME}' locale are not found in the '${QT_TRANSLATIONS_DIR}' folder.")
                    endif()
                endif ()
            endforeach(QM_FILE)

            list(REMOVE_DUPLICATES QM_FILES)
        endif ()

        if(QM_FILES)
            add_custom_target(qm-files
                COMMAND ${CMAKE_COMMAND} -E make_directory ${QT_OPENMW_TRANSLATIONS_PATH}
                COMMAND ${CMAKE_COMMAND} -E copy_if_different ${QM_FILES} ${QT_OPENMW_TRANSLATIONS_PATH}
                DEPENDS ${QM_FILES}
                COMMENT "Copy *.qm files to resources folder")
        else()
            add_custom_target(qm-files
                COMMENT "No translation files to copy (lrelease not found or no .ts files)")
        endif()
    endif ()
endif()
