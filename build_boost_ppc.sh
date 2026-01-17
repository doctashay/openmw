#!/bin/bash
# Build Boost 1.76.0 for PowerPC macOS 10.5 with gcc-mp-14
# This ensures ABI compatibility with OpenMW build

set -e

BOOST_VERSION=1.76.0
BOOST_MAJOR_MINOR="1_76"
BOOST_DIR="/tmp/boost_${BOOST_VERSION}"
INSTALL_PREFIX="/opt/local/boost-gcc14-ppc"
SDK_PATH="/Developer/SDKs/MacOSX10.5.sdk"

echo "=== Building Boost ${BOOST_VERSION} for PowerPC macOS 10.5 ==="
echo ""

# Verify SDK
if [ ! -d "$SDK_PATH" ]; then
    echo "ERROR: SDK not found at $SDK_PATH"
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
echo ""

# Download Boost if needed
if [ ! -d "$BOOST_DIR" ]; then
    echo "Downloading Boost ${BOOST_VERSION}..."
    cd /tmp
    if [ ! -f "boost_${BOOST_MAJOR_MINOR}_0.tar.gz" ]; then
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

./bootstrap.sh --with-toolset=gcc --prefix="$INSTALL_PREFIX"

echo ""
echo "Building Boost libraries (this will take a while)..."
echo ""

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
echo "To use this Boost installation, add to your CMake command:"
echo "  -D Boost_ROOT=$INSTALL_PREFIX"
echo ""
echo "Or set environment variable:"
echo "  export Boost_ROOT=$INSTALL_PREFIX"
echo ""
