#!/bin/bash
# Build Boost 1.81.0 for PowerPC macOS 10.5 with gcc-mp-14 and C++17
# This ensures ABI compatibility with OpenMW build
# Builds only required components (iostreams, program_options)
# Builds both static and shared libraries with C++17 ABI

set -e

BOOST_VERSION=1.81.0
BOOST_MAJOR_MINOR="1_81"
BOOST_DIR="/tmp/boost_${BOOST_VERSION}"
INSTALL_PREFIX="/opt/local/boost181-gcc14-cxx17-ppc"
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
echo "  C++ standard: C++17"
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

# C++ standard selection: set to 17 for C++17
CXXSTD="17"

# ABI selection: default to new libstdc++ ABI unless overridden (ABI=0).
# Leaving it empty lets GCC use its default language mode.
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

# PowerPC on 10.5 dislikes unaligned accesses; keep code conservative.
ALIGN_FLAGS="-mstrict-align -fno-strict-aliasing"
# Suppress noisy warnings while building Boost.
WARN_FLAGS="-w"

echo "Bootstrapping Boost with gcc-mp-14..."
# Bootstrap with your compiler
export CC="$GCC_MP14"
export CXX="$GXX_MP14"
export CXXFLAGS="$CXXSTD_FLAG $ABI_FLAG -mmacosx-version-min=10.5 -arch ppc -isysroot $SDK_PATH $ALIGN_FLAGS $WARN_FLAGS"
export LDFLAGS="-mmacosx-version-min=10.5 -arch ppc -isysroot $SDK_PATH"

echo "Compiler flags:"
echo "  CXXSTD: ${CXXSTD:-default} ($CXXSTD_FLAG)"
echo "  ABI: ${ABI_VALUE} ($ABI_FLAG)"
echo ""

# Clean previous bootstrap if it exists
if [ -f "b2" ]; then
    echo "Cleaning previous bootstrap..."
    rm -f b2 bjam project-config.jam
fi

./bootstrap.sh --with-toolset=gcc --prefix="$INSTALL_PREFIX"

echo ""
echo "Building Boost libraries (this will take a while)..."
echo ""

# Create user-config.jam in the Boost root directory
cat > user-config.jam <<EOF
using gcc : 14 : $GXX_MP14
    : <cxxflags>"$CXXSTD_FLAG $ABI_FLAG -mmacosx-version-min=10.5 -arch ppc -isysroot $SDK_PATH $ALIGN_FLAGS $WARN_FLAGS"
      <linkflags>"-mmacosx-version-min=10.5 -arch ppc -isysroot $SDK_PATH"
    ;
EOF

echo "Created user-config.jam"
echo ""

# Detect number of CPU cores for parallel compilation
if command -v sysctl >/dev/null 2>&1; then
    # macOS
    NUM_JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo "2")
elif command -v nproc >/dev/null 2>&1; then
    # Linux
    NUM_JOBS=$(nproc 2>/dev/null || echo "2")
else
    NUM_JOBS=2
fi

echo "Using $NUM_JOBS parallel jobs for faster compilation"
echo ""

# Build only the components required by OpenMW:
# - program_options: command-line argument parsing
# - iostreams: stream I/O (compression/decompression)
# 
# Build settings:
# - Both shared (.dylib) and static (.a) libraries
# - C++17 standard (forced via multiple methods for reliability)
# - Multi-threaded variant
# - Release optimization level
#
# The user-config.jam will be automatically picked up by b2
# We specify toolset=gcc-14 to match the version in user-config.jam
# -j$NUM_JOBS enables parallel compilation
# Force C++17 via both cxxstd and direct cxxflags to override any defaults
./b2 \
    -j$NUM_JOBS \
    toolset=gcc-14 \
    architecture=power \
    address-model=32_64 \
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

# Fix install_name for dylibs to use absolute paths
echo ""
echo "Fixing install_name for Boost dylibs..."
for dylib in "$INSTALL_PREFIX/lib"/libboost_*.dylib; do
    if [ -f "$dylib" ]; then
        dylib_name=$(basename "$dylib")
        # Get current install_name
        current_name=$(otool -D "$dylib" | tail -n 1)
        
        # Set install_name to absolute path in install directory
        new_name="$INSTALL_PREFIX/lib/$dylib_name"
        
        if [ "$current_name" != "$new_name" ]; then
            echo "  Fixing install_name for $dylib_name"
            echo "    From: $current_name"
            echo "    To: $new_name"
            install_name_tool -id "$new_name" "$dylib" || echo "    Warning: install_name_tool failed (may need sudo)"
        fi
    fi
done

echo ""
echo "=== Boost installation complete! ==="
echo ""
echo "Boost has been installed to: $INSTALL_PREFIX"
echo ""
echo "To use this Boost installation, add to your CMake command:"
echo "  -D Boost_ROOT=$INSTALL_PREFIX"
echo ""
echo "Or set environment variable (recommended):"
echo "  export Boost_ROOT=$INSTALL_PREFIX"
echo ""
echo "After setting Boost_ROOT, reconfigure CMake:"
echo "  cd build_test"
echo "  cmake ..  # (with all your other cmake args)"
echo ""