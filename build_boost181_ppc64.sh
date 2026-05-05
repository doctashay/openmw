#!/bin/bash
# Build Boost 1.81.0 for PowerPC 64-bit (ppc64) macOS 10.5 with gcc-mp-14 and C++17
# Use this for OpenMW ppc64 builds to avoid the 32-bit address space limit.
# Builds only required components (program_options, iostreams).
# Builds both static and shared libraries, 64-bit only.

set -e

BOOST_VERSION=1.81.0
BOOST_MAJOR_MINOR="1_81"
BOOST_DIR="/tmp/boost_${BOOST_VERSION}_ppc64"
INSTALL_PREFIX="/opt/local/boost181-gcc14-cxx17-ppc64"
SDK_PATH="/Developer/SDKs/MacOSX10.5.sdk"

echo "=== Building Boost ${BOOST_VERSION} for PowerPC 64-bit (ppc64) macOS 10.5 ==="
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
echo "  C++ standard: C++17"
echo "  Architecture: ppc64 (64-bit PowerPC only)"
echo "  Install prefix: $INSTALL_PREFIX"
echo "  SDK: $SDK_PATH"
echo ""

# Verify compiler can target ppc64
echo "Verifying compiler can target ppc64..."
if ! $GXX_MP14 -arch ppc64 -E -x c++ /dev/null -o /dev/null 2>/dev/null; then
    echo "WARNING: Compiler may not support ppc64 architecture"
    echo "Continuing anyway..."
fi
echo ""

# Download and extract Boost if needed (use a separate dir from 32-bit build to avoid overwriting)
if [ ! -d "$BOOST_DIR" ]; then
    echo "Downloading Boost ${BOOST_VERSION}..."
    cd /tmp
    if [ ! -f "boost_${BOOST_MAJOR_MINOR}_0.tar.gz" ]; then
        echo "Downloading from Boost archives..."
        wget https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_MAJOR_MINOR}_0.tar.gz || \
        wget https://boostorg.jfrog.io/artifactory/main/release/${BOOST_VERSION}/source/boost_${BOOST_MAJOR_MINOR}_0.tar.gz
    fi
    echo "Extracting Boost (ppc64 build dir)..."
    tar xzf boost_${BOOST_MAJOR_MINOR}_0.tar.gz
    mv boost_${BOOST_MAJOR_MINOR}_0 "$(basename "$BOOST_DIR")"
fi

cd "$BOOST_DIR"

# C++ standard selection: set to 17 for C++17
CXXSTD="17"

# ABI selection: default to new libstdc++ ABI unless overridden (ABI=0).
ABI_VALUE="${ABI:-1}"
if [ "$ABI_VALUE" = "0" ]; then
    ABI_FLAG="-D_GLIBCXX_USE_CXX11_ABI=0"
else
    ABI_FLAG="-D_GLIBCXX_USE_CXX11_ABI=1"
fi

# Build CXXSTD flag
if [ -n "$CXXSTD" ]; then
    CXXSTD_FLAG="-std=c++$CXXSTD"
else
    CXXSTD_FLAG=""
fi

# PowerPC on 10.5: conservative flags for ppc64
ALIGN_FLAGS="-mstrict-align -fno-strict-aliasing"
WARN_FLAGS="-w"

echo "Bootstrapping Boost with gcc-mp-14 (ppc64)..."
export CC="$GCC_MP14"
export CXX="$GXX_MP14"
export CXXFLAGS="$CXXSTD_FLAG $ABI_FLAG -mmacosx-version-min=10.5 -arch ppc64 -isysroot $SDK_PATH $ALIGN_FLAGS $WARN_FLAGS"
export LDFLAGS="-mmacosx-version-min=10.5 -arch ppc64 -isysroot $SDK_PATH"

echo "Compiler flags:"
echo "  CXXSTD: ${CXXSTD:-default} ($CXXSTD_FLAG)"
echo "  ABI: ${ABI_VALUE} ($ABI_FLAG)"
echo "  address-model: 64 only"
echo ""

# Clean previous bootstrap if it exists
if [ -f "b2" ]; then
    echo "Cleaning previous bootstrap..."
    rm -f b2 bjam project-config.jam
fi

./bootstrap.sh --with-toolset=gcc --prefix="$INSTALL_PREFIX"

echo ""
echo "Building Boost libraries for ppc64 (this will take a while)..."
echo ""

# user-config.jam for ppc64
cat > user-config.jam <<EOF
using gcc : 14 : $GXX_MP14
    : <cxxflags>"$CXXSTD_FLAG $ABI_FLAG -mmacosx-version-min=10.5 -arch ppc64 -isysroot $SDK_PATH $ALIGN_FLAGS $WARN_FLAGS"
      <linkflags>"-mmacosx-version-min=10.5 -arch ppc64 -isysroot $SDK_PATH"
    ;
EOF

echo "Created user-config.jam (ppc64)"
echo ""

# Parallel jobs
if command -v sysctl >/dev/null 2>&1; then
    NUM_JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo "2")
elif command -v nproc >/dev/null 2>&1; then
    NUM_JOBS=$(nproc 2>/dev/null || echo "2")
else
    NUM_JOBS=2
fi

echo "Using $NUM_JOBS parallel jobs"
echo ""

# address-model=64: 64-bit only (ppc64). architecture=power.
./b2 \
    -j$NUM_JOBS \
    toolset=gcc-14 \
    architecture=power \
    address-model=64 \
    cxxstd=17 \
    cxxflags="-std=gnu++17" \
    --with-program_options \
    --with-iostreams \
    --prefix="$INSTALL_PREFIX" \
    variant=release \
    link=shared,static \
    threading=multi \
    install

echo ""
echo "=== Boost ppc64 build complete! ==="
echo ""

# Verify the build
echo "Verifying ppc64 architecture in built libraries..."
if [ -f "$INSTALL_PREFIX/lib/libboost_program_options.dylib" ]; then
    echo "Checking libboost_program_options.dylib:"
    lipo -info "$INSTALL_PREFIX/lib/libboost_program_options.dylib" || true
elif [ -f "$INSTALL_PREFIX/lib/libboost_program_options.a" ]; then
    echo "Checking libboost_program_options.a:"
    lipo -info "$INSTALL_PREFIX/lib/libboost_program_options.a" || true
fi

# Fix install_name for dylibs
echo ""
echo "Fixing install_name for Boost dylibs..."
for dylib in "$INSTALL_PREFIX/lib"/libboost_*.dylib; do
    if [ -f "$dylib" ]; then
        dylib_name=$(basename "$dylib")
        current_name=$(otool -D "$dylib" | tail -n 1)
        new_name="$INSTALL_PREFIX/lib/$dylib_name"
        if [ "$current_name" != "$new_name" ]; then
            echo "  Fixing install_name for $dylib_name"
            install_name_tool -id "$new_name" "$dylib" || echo "    Warning: install_name_tool failed (may need sudo)"
        fi
    fi
done

echo ""
echo "=== Boost ppc64 installation complete! ==="
echo ""
echo "Boost (ppc64) has been installed to: $INSTALL_PREFIX"
echo ""
echo "Next: Configure OpenMW for ppc64 using test_build_ppc64.sh (it will auto-detect this prefix),"
echo "or set: export Boost_ROOT=$INSTALL_PREFIX"
echo ""
echo "OSG and MyGUI are built in-tree by CMake when you run test_build_ppc64.sh;"
echo "CMAKE_OSX_ARCHITECTURES=ppc64 ensures they are built for ppc64 as well."
echo ""
