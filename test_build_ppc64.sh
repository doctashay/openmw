#!/bin/bash
# Test build for macOS 10.5 PowerPC 64-bit (ppc64)
# Same configuration as test_build_10.5.sh but CMAKE_OSX_ARCHITECTURES=ppc64.
# Run build_boost181_ppc64.sh first to build Boost for ppc64.
# OSG and MyGUI are built in-tree by this script (OPENMW_USE_SYSTEM_OSG=OFF, OPENMW_USE_SYSTEM_MYGUI=OFF);
# CMAKE_OSX_ARCHITECTURES=ppc64 is passed to the whole tree, so they are built for ppc64 automatically.
# If you set OSG_MYGUI_ROOT, that prefix must contain OSG/MyGUI built for ppc64.

set -e

ROOT_DIR="$(pwd)"
BUILD_DIR="${ROOT_DIR}/build_test_ppc64"
SDK_PATH="/Developer/SDKs/MacOSX10.5.sdk"
OSG_SOURCE_DIR="${ROOT_DIR}/extern/osg"
MYGUI_SOURCE_DIR="${ROOT_DIR}/extern/mygui"
NUM_JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo "2")

echo "=== Testing macOS 10.5 PowerPC 64-bit (ppc64) Build Configuration ==="
echo ""

# Verify SDK
if [ ! -d "$SDK_PATH" ]; then
    echo "ERROR: SDK not found at $SDK_PATH"
    exit 1
fi

# Verify compilers exist and get their absolute paths
if ! command -v gcc-mp-14 >/dev/null 2>&1; then
    echo "ERROR: gcc-mp-14 not found. Please install via MacPorts: sudo port install gcc14"
    exit 1
fi

if ! command -v g++-mp-14 >/dev/null 2>&1; then
    echo "ERROR: g++-mp-14 not found. Please install via MacPorts: sudo port install gcc14"
    exit 1
fi

# Get absolute paths to compilers
GCC_MP14=$(which gcc-mp-14)
GXX_MP14=$(which g++-mp-14)

echo "Using compilers:"
echo "  C compiler: $GCC_MP14"
echo "  C++ compiler: $GXX_MP14"
echo "  Architecture: ppc64 (64-bit PowerPC)"
echo ""

# Set environment variables so CMake uses the correct compilers
export CC="$GCC_MP14"
export CXX="$GXX_MP14"

# Check for Boost_ROOT (prefer ppc64-specific prefix)
if [ -z "$Boost_ROOT" ]; then
    if [ -d "/opt/local/boost181-gcc14-cxx17-ppc64" ]; then
        export Boost_ROOT="/opt/local/boost181-gcc14-cxx17-ppc64"
        echo "Auto-detected Boost_ROOT (ppc64): $Boost_ROOT"
    elif [ -d "/opt/local/boost181-gcc14-ppc64" ]; then
        export Boost_ROOT="/opt/local/boost181-gcc14-ppc64"
        echo "Auto-detected Boost_ROOT (ppc64): $Boost_ROOT"
    elif [ -d "/opt/local/boost-gcc14-ppc64" ]; then
        export Boost_ROOT="/opt/local/boost-gcc14-ppc64"
        echo "Auto-detected Boost_ROOT (ppc64): $Boost_ROOT"
    else
        echo "WARNING: Boost_ROOT not set and no ppc64 Boost found in common locations"
        echo "Build Boost for ppc64 and set Boost_ROOT, or pass -D Boost_ROOT=/path/to/boost-ppc64 to CMake"
    fi
else
    echo "Using Boost_ROOT from environment: $Boost_ROOT"
    if [ ! -d "$Boost_ROOT" ]; then
        echo "WARNING: Boost_ROOT is set but directory doesn't exist: $Boost_ROOT"
    fi
fi
echo ""

# Init submodules when .gitmodules exists
if [ -f "${ROOT_DIR}/.gitmodules" ]; then
    echo "Initializing submodules..."
    (cd "$ROOT_DIR" && git submodule update --init extern/osg 2>/dev/null) || true
    (cd "$ROOT_DIR" && git submodule update --init extern/mygui 2>/dev/null) || {
        echo "Note: extern/mygui submodule not registered in this repo; CMake will use FetchContent for MyGUI."
    }
fi
if [ ! -d "$OSG_SOURCE_DIR" ] || [ ! -f "${OSG_SOURCE_DIR}/CMakeLists.txt" ]; then
    echo "ERROR: OSG source not found at $OSG_SOURCE_DIR"
    echo "Ensure submodules are inited: git submodule update --init extern/osg extern/mygui"
    echo "See SUBMODULES.md for using your OSG/MyGUI fork and Darwin patches."
    exit 1
fi
if [ ! -d "$MYGUI_SOURCE_DIR" ] || [ ! -f "${MYGUI_SOURCE_DIR}/CMakeLists.txt" ]; then
    echo "WARNING: MyGUI submodule not found at $MYGUI_SOURCE_DIR; CMake will use FetchContent for MyGUI."
fi
echo ""

# Ensure we configure OpenMW from the repo root
cd "$ROOT_DIR"

# Clean and create build directory only when explicitly requested.
if [ "${CLEAN_BUILD_DIR:-0}" = "1" ]; then
    rm -rf "$BUILD_DIR"
else
    echo "Preserving existing build directory: $BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "Running CMake configuration (ppc64)..."
echo ""

# Same options as test_build_10.5.sh but CMAKE_OSX_ARCHITECTURES=ppc64
CMAKE_ARGS=(
    -D CMAKE_BUILD_TYPE=RelWithDebInfo
    -D CMAKE_OSX_DEPLOYMENT_TARGET=10.5
    -D CMAKE_OSX_ARCHITECTURES=ppc64
    -D CMAKE_OSX_SYSROOT="$SDK_PATH"
    -D CMAKE_CXX_STANDARD=17
    -D CMAKE_C_FLAGS_RELWITHDEBINFO="-O2 -g -DNDEBUG"
    -D CMAKE_CXX_FLAGS_RELWITHDEBINFO="-O2 -g -DNDEBUG"
    -D OPENMW_MACOSX_10_5_BUILD=ON
    -D OPENMW_POWERPC_BUILD=ON
    -D CMAKE_C_COMPILER="$GCC_MP14"
    -D CMAKE_CXX_COMPILER="$GXX_MP14"
    -D OPENMW_UNITY_BUILD=OFF
    -D OPENMW_OSG_SINGLE_THREADED=OFF
    -D BUILD_LAUNCHER=OFF
    -D BUILD_OPENCS=OFF
    -D BUILD_WIZARD=OFF
    -D BUILD_OPENCS_TESTS=OFF
    -D BUILD_OPENMW_TESTS=OFF
    -D BUILD_COMPONENTS_TESTS=OFF
    -D BUILD_BENCHMARKS=OFF
    -D BUILD_DOCS=OFF
    -D BUILD_MWINIIMPORTER=ON
    -D BUILD_ESSIMPORTER=OFF
    -D BUILD_NIFTEST=OFF
    -D BUILD_NAVMESHTOOL=OFF
    -D BUILD_BULLETOBJECTTOOL=OFF
    -D USE_QT=FALSE
    -D BUILD_OPENMW=ON
    -D BUILD_BSATOOL=ON
    -D BUILD_ESMTOOL=ON
    -D Boost_USE_STATIC_LIBS=ON
    -D Boost_USE_STATIC_RUNTIME=ON
    -D MYGUI_STATIC=ON
    -D OPENMW_USE_SYSTEM_YAML_CPP=OFF
    -D OPENMW_USE_SYSTEM_BULLET=OFF
    -D OPENMW_USE_SYSTEM_OSG=OFF
    -D OPENMW_USE_SYSTEM_MYGUI=OFF
    -D OPENMW_USE_SYSTEM_ICU=ON
    -D OPENMW_LTO_BUILD=OFF
)

# Add Boost_ROOT if set
if [ -n "$Boost_ROOT" ]; then
    CMAKE_ARGS+=(-D Boost_ROOT="$Boost_ROOT")
fi

# Optional: use prebuilt OSG/MyGUI from a prefix (must be built for ppc64)
if [ -n "$OSG_MYGUI_ROOT" ] && [ -d "$OSG_MYGUI_ROOT" ]; then
    export MYGUI_HOME="$OSG_MYGUI_ROOT"
    CMAKE_ARGS+=(
        -D OPENMW_USE_SYSTEM_OSG=ON
        -D OPENMW_USE_SYSTEM_MYGUI=ON
        -D CMAKE_PREFIX_PATH="$OSG_MYGUI_ROOT"
        -D OSG_DIR="$OSG_MYGUI_ROOT"
        -D OpenSceneGraph_DIR="$OSG_MYGUI_ROOT/lib64/cmake/OpenSceneGraph"
        -D OSG_STATIC=ON
    )
    echo "Using prebuilt OSG and MyGUI from: $OSG_MYGUI_ROOT (must be ppc64)"
else
    echo "Building OSG and MyGUI in-tree from extern/osg and extern/mygui (submodules) for ppc64."
fi

# Add ccache if available
if command -v ccache &> /dev/null; then
    CMAKE_ARGS+=(
        -D CMAKE_C_COMPILER_LAUNCHER="ccache"
        -D CMAKE_CXX_COMPILER_LAUNCHER="ccache"
    )
    echo "Using ccache for compiler caching"
else
    echo "ccache not found - install it for faster rebuilds: sudo port install ccache"
fi

cmake "${CMAKE_ARGS[@]}" .. 2>&1 | tee cmake_test_ppc64.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo "✓ CMake configuration (ppc64) successful!"
    echo "  Build dir: $BUILD_DIR"
    echo "  Log: cmake_test_ppc64.log"
    echo ""
    echo "Build with:"
    echo "  cd $BUILD_DIR && make -j\$(sysctl -n hw.ncpu)"
    echo ""
    echo "Note: ppc64 avoids the 32-bit virtual address space limit; low-memory settings may still help but are not required to avoid OOM."
else
    echo ""
    echo "✗ CMake configuration (ppc64) failed"
    echo "Check cmake_test_ppc64.log for errors"
    exit 1
fi
