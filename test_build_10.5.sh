#!/bin/bash
# Minimal test build for macOS 10.5 PowerPC
# This script tests if CMake can configure the project

set -e

BUILD_DIR="build_test"
SDK_PATH="/Developer/SDKs/MacOSX10.5.sdk"

echo "=== Testing macOS 10.5 PowerPC Build Configuration ==="
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
echo ""

# Set environment variables so CMake uses the correct compilers
export CC="$GCC_MP14"
export CXX="$GXX_MP14"

# Check for Boost_ROOT
if [ -z "$Boost_ROOT" ]; then
    # Try common locations
    if [ -d "/opt/local/boost181-gcc14-ppc" ]; then
        export Boost_ROOT="/opt/local/boost181-gcc14-ppc"
        echo "Auto-detected Boost_ROOT: $Boost_ROOT"
    elif [ -d "/opt/local/boost-gcc14-ppc" ]; then
        export Boost_ROOT="/opt/local/boost-gcc14-ppc"
        echo "Auto-detected Boost_ROOT: $Boost_ROOT"
    else
        echo "WARNING: Boost_ROOT not set and not found in common locations"
        echo "Set Boost_ROOT environment variable or pass -D Boost_ROOT=/path/to/boost to CMake"
    fi
else
    echo "Using Boost_ROOT from environment: $Boost_ROOT"
    if [ ! -d "$Boost_ROOT" ]; then
        echo "WARNING: Boost_ROOT is set but directory doesn't exist: $Boost_ROOT"
    fi
fi
echo ""
# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "Running CMake configuration test..."
echo ""

# Minimal CMake configuration - just game engine, no Qt
# Optimized for faster builds: unity builds, RelWithDebInfo, ccache, minimal targets
CMAKE_ARGS=(
    -D CMAKE_BUILD_TYPE=RelWithDebInfo
    -D CMAKE_OSX_DEPLOYMENT_TARGET=10.5
    -D CMAKE_OSX_ARCHITECTURES=ppc
    -D CMAKE_OSX_SYSROOT="$SDK_PATH"
    -D OPENMW_MACOSX_10_5_BUILD=ON
    -D OPENMW_POWERPC_BUILD=ON
    -D CMAKE_C_COMPILER="$GCC_MP14"
    -D CMAKE_CXX_COMPILER="$GXX_MP14"
    -D OPENMW_UNITY_BUILD=ON
    -D BUILD_LAUNCHER=OFF
    -D BUILD_OPENCS=OFF
    -D BUILD_WIZARD=OFF
    -D BUILD_OPENCS_TESTS=OFF
    -D BUILD_OPENMW_TESTS=OFF
    -D BUILD_COMPONENTS_TESTS=OFF
    -D BUILD_BENCHMARKS=OFF
    -D BUILD_DOCS=OFF
    -D BUILD_MWINIIMPORTER=OFF
    -D BUILD_ESSIMPORTER=OFF
    -D BUILD_NIFTEST=OFF
    -D BUILD_NAVMESHTOOL=OFF
    -D BUILD_BULLETOBJECTTOOL=OFF
    -D USE_QT=FALSE
    -D BUILD_OPENMW=ON
    -D BUILD_BSATOOL=ON
    -D BUILD_ESMTOOL=ON
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

# Add ccache if available (speeds up rebuilds significantly)
if command -v ccache &> /dev/null; then
    CMAKE_ARGS+=(
        -D CMAKE_C_COMPILER_LAUNCHER="ccache"
        -D CMAKE_CXX_COMPILER_LAUNCHER="ccache"
    )
    echo "Using ccache for compiler caching"
else
    echo "ccache not found - install it for faster rebuilds: sudo port install ccache"
fi

cmake "${CMAKE_ARGS[@]}" .. 2>&1 | tee cmake_test.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo ""
    echo "✓ CMake configuration successful!"
    echo "Check cmake_test.log for details"
    echo ""
    echo "Next: Try building a simple component:"
    echo "  cd $BUILD_DIR && make bsatool -j1"
else
    echo ""
    echo "✗ CMake configuration failed"
    echo "Check cmake_test.log for errors"
    exit 1
fi
