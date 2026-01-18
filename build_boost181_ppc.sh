#!/bin/bash
# Build Boost 1.81.0 for PowerPC macOS 10.5 with gcc-mp-14
# This ensures ABI compatibility with OpenMW build
# Updated for Boost 1.81

set -e

BOOST_VERSION=1.81.0
BOOST_MAJOR_MINOR="1_81"
BOOST_DIR="/tmp/boost_${BOOST_VERSION}"
INSTALL_PREFIX="/opt/local/boost181-gcc14-ppc"
SDK_PATH="/Developer/SDKs/MacOSX10.5.sdk"

echo "=== Building Boost ${BOOST_VERSION} for PowerPC macOS 10.5 ==="
echo ""

# Verify SDK
if [ ! -d "$SDK_PATH" ]; then
    echo "ERROR: SDK not found at $SDK_PATH"
    echo "Please ensure you have the macOS 10.5 SDK installed"
    exit 1
fi

# Verify compilers
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
echo "  Install prefix: $INSTALL_PREFIX"
echo "  SDK: $SDK_PATH"
echo ""

# Verify compiler can target PowerPC
echo "Verifying compiler can target PowerPC..."
if ! $GXX_MP14 -arch ppc -E -x c++ /dev/null -o /dev/null 2>/dev/null; then
    echo "WARNING: Compiler may not support PowerPC architecture"
    echo "Continuing anyway..."
fi
echo ""

# Download Boost if needed
if [ ! -d "$BOOST_DIR" ]; then
    echo "Downloading Boost ${BOOST_VERSION}..."
    cd /tmp
    if [ ! -f "boost_${BOOST_MAJOR_MINOR}_0.tar.gz" ]; then
        echo "Downloading from Boost archives..."
        wget https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_MAJOR_MINOR}_0.tar.gz || \
        wget https://boostorg.jfrog.io/artifactory/main/release/${BOOST_VERSION}/source/boost_${BOOST_MAJOR_MINOR}_0.tar.gz
    fi
    echo "Extracting Boost..."
    tar xzf boost_${BOOST_MAJOR_MINOR}_0.tar.gz
    mv boost_${BOOST_MAJOR_MINOR}_0 boost_${BOOST_VERSION}
fi

cd "$BOOST_DIR"

echo "Bootstrapping Boost with gcc-mp-14..."
# Bootstrap with your compiler
export CC="$GCC_MP14"
export CXX="$GXX_MP14"
export CXXFLAGS="-std=c++20 -mmacosx-version-min=10.5 -arch ppc -isysroot $SDK_PATH"
export LDFLAGS="-mmacosx-version-min=10.5 -arch ppc -isysroot $SDK_PATH"

# Clean previous bootstrap if it exists
if [ -f "b2" ]; then
    echo "Cleaning previous bootstrap..."
    rm -f b2 bjam project-config.jam
fi

./bootstrap.sh --with-toolset=gcc --prefix="$INSTALL_PREFIX"

echo ""
echo "Building Boost libraries (this will take a while)..."
echo ""

# Create user-config.jam to ensure correct compiler settings
cat > user-config.jam <<EOF
using gcc : : $GXX_MP14
    : <cxxflags>"-std=c++20 -mmacosx-version-min=10.5 -arch ppc -isysroot $SDK_PATH"
      <linkflags>"-mmacosx-version-min=10.5 -arch ppc -isysroot $SDK_PATH"
    ;
EOF

# Build with your exact settings
# Note: Boost's b2 uses different flag names
./b2 \
    toolset=gcc \
    cxx="$GXX_MP14" \
    cxxflags="-std=c++20 -mmacosx-version-min=10.5 -arch ppc -isysroot $SDK_PATH" \
    linkflags="-mmacosx-version-min=10.5 -arch ppc -isysroot $SDK_PATH" \
    architecture=power \
    address-model=32_64 \
    --with-program_options \
    --with-iostreams \
    --prefix="$INSTALL_PREFIX" \
    variant=release \
    link=shared,static \
    threading=multi \
    install

echo ""
echo "=== Boost build complete! ==="
echo ""

# Verify the build
echo "Verifying PowerPC architecture in built libraries..."
if [ -f "$INSTALL_PREFIX/lib/libboost_program_options.dylib" ]; then
    echo "Checking libboost_program_options.dylib:"
    lipo -info "$INSTALL_PREFIX/lib/libboost_program_options.dylib" || true
elif [ -f "$INSTALL_PREFIX/lib/libboost_program_options.a" ]; then
    echo "Checking libboost_program_options.a:"
    lipo -info "$INSTALL_PREFIX/lib/libboost_program_options.a" || true
fi

echo ""
echo "To use this Boost installation, add to your CMake command:"
echo "  -D Boost_ROOT=$INSTALL_PREFIX"
echo ""
echo "Or set environment variable:"
echo "  export Boost_ROOT=$INSTALL_PREFIX"
echo ""
