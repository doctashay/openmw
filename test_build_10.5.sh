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

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "Running CMake configuration test..."
echo ""

# Minimal CMake configuration - just game engine, no Qt
# Unity builds enabled for faster compilation, but all Qt-dependent targets disabled
cmake \
    -D CMAKE_BUILD_TYPE=Debug \
    -D CMAKE_OSX_DEPLOYMENT_TARGET=10.5 \
    -D CMAKE_OSX_ARCHITECTURES=ppc \
    -D CMAKE_OSX_SYSROOT="$SDK_PATH" \
    -D OPENMW_MACOSX_10_5_BUILD=ON \
    -D OPENMW_POWERPC_BUILD=ON \
    -D CMAKE_C_COMPILER="gcc-mp-14" \
    -D CMAKE_CXX_COMPILER="g++-mp-14" \
    -D OPENMW_UNITY_BUILD=ON \
    -D BUILD_LAUNCHER=OFF \
    -D BUILD_OPENCS=OFF \
    -D BUILD_WIZARD=OFF \
    -D BUILD_OPENCS_TESTS=OFF \
    -D USE_QT=FALSE \
    -D BUILD_OPENMW=ON \
    -D BUILD_BSATOOL=ON \
    -D BUILD_ESMTOOL=ON \
    -D OPENMW_USE_SYSTEM_YAML_CPP=OFF \
    -D OPENMW_USE_SYSTEM_BULLET=OFF \
    -D OPENMW_USE_SYSTEM_OSG=OFF \
    -D OPENMW_USE_SYSTEM_MYGUI=OFF \
    .. 2>&1 | tee cmake_test.log

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
