#!/bin/bash
# Configure and optionally build OpenMW for PowerPC macOS (ppc or ppc64).
# Usage: ./build_ppc.sh [ppc|ppc64]   (default: ppc)
#
# This script intentionally keeps OSG generic on PPC:
# - RelWithDebInfo builds
# - -O2 only
# - no CPU-specific tuning flags such as -mcpu/-mtune
# - static in-tree OSG/MyGUI unless OSG_MYGUI_ROOT is supplied

set -e

ARCH="${1:-ppc}"
if [ "$ARCH" != "ppc" ] && [ "$ARCH" != "ppc64" ]; then
    echo "Usage: $0 [ppc|ppc64]"
    exit 1
fi

ROOT_DIR="$(pwd)"
BUILD_DIR="${ROOT_DIR}/build_${ARCH}"
SDK_PATH="/Developer/SDKs/MacOSX10.5.sdk"
NUM_JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo "2")

echo "=== OpenMW PowerPC Build ($ARCH) ==="
echo ""

# --- Verify SDK ----------------------------------------------------------
[ -d "$SDK_PATH" ] || { echo "ERROR: SDK not found at $SDK_PATH"; exit 1; }

# --- Verify compilers ----------------------------------------------------
for bin in gcc-mp-14 g++-mp-14; do
    command -v "$bin" >/dev/null 2>&1 || {
        echo "ERROR: $bin not found. Install via MacPorts: sudo port install gcc14"
        exit 1
    }
done
GCC_MP14=$(which gcc-mp-14)
GXX_MP14=$(which g++-mp-14)
echo "C:   $GCC_MP14"
echo "C++: $GXX_MP14"
echo "Arch: $ARCH"
echo ""
export CC="$GCC_MP14"
export CXX="$GXX_MP14"

# --- Boost auto-detection ------------------------------------------------
if [ -z "$Boost_ROOT" ]; then
    for candidate in \
        "/opt/local/boost181-gcc14-cxx17-${ARCH}" \
        "/opt/local/boost181-gcc14-${ARCH}" \
        "/opt/local/boost-gcc14-${ARCH}"
    do
        if [ -d "$candidate" ]; then
            export Boost_ROOT="$candidate"
            echo "Auto-detected Boost_ROOT: $Boost_ROOT"
            break
        fi
    done
    [ -n "$Boost_ROOT" ] || echo "WARNING: Boost_ROOT not set and not found in common locations."
else
    echo "Boost_ROOT: $Boost_ROOT"
    [ -d "$Boost_ROOT" ] || echo "WARNING: Boost_ROOT set but directory missing: $Boost_ROOT"
fi
echo ""

# --- Submodules ----------------------------------------------------------
if [ -f "${ROOT_DIR}/.gitmodules" ]; then
    echo "Initializing submodules..."
    git -C "$ROOT_DIR" submodule update --init extern/osg extern/mygui 2>/dev/null || \
        echo "Note: one or more submodules not registered; CMake will use FetchContent for missing ones."
fi
[ -f "${ROOT_DIR}/extern/osg/CMakeLists.txt" ] || {
    echo "ERROR: OSG source not found at extern/osg. Run: git submodule update --init extern/osg"
    exit 1
}
echo ""

# --- Build directory -----------------------------------------------------
if [ "${CLEAN_BUILD_DIR:-0}" = "1" ]; then
    rm -rf "$BUILD_DIR"
else
    echo "Preserving existing build directory: $BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# --- CMake args ----------------------------------------------------------
CMAKE_ARGS=(
    -D CMAKE_BUILD_TYPE=RelWithDebInfo
    -D CMAKE_OSX_DEPLOYMENT_TARGET=10.5
    -D CMAKE_OSX_ARCHITECTURES="$ARCH"
    -D CMAKE_OSX_SYSROOT="$SDK_PATH"
    -D CMAKE_CXX_STANDARD=17
    -D CMAKE_C_FLAGS_RELWITHDEBINFO="-O2 -g -DNDEBUG"
    -D CMAKE_CXX_FLAGS_RELWITHDEBINFO="-O2 -g -DNDEBUG"
    -D CMAKE_C_COMPILER="$GCC_MP14"
    -D CMAKE_CXX_COMPILER="$GXX_MP14"
    -D OPENMW_MACOSX_10_5_BUILD=ON
    -D OPENMW_POWERPC_BUILD=ON
    -D OPENMW_UNITY_BUILD=OFF
    -D OPENMW_LTO_BUILD=OFF
    -D OPENMW_OSG_SINGLE_THREADED=OFF
    -D BUILD_OPENMW=ON
    -D BUILD_BSATOOL=ON
    -D BUILD_ESMTOOL=ON
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
    -D Boost_USE_STATIC_LIBS=ON
    -D Boost_USE_STATIC_RUNTIME=ON
    -D OSG_STATIC=ON
    -D MYGUI_STATIC=ON
    -D OPENMW_USE_SYSTEM_YAML_CPP=OFF
    -D OPENMW_USE_SYSTEM_BULLET=OFF
    -D OPENMW_USE_SYSTEM_ICU=ON
    -D OPENMW_USE_SYSTEM_OSG=OFF
    -D OPENMW_USE_SYSTEM_MYGUI=OFF
)

[ -n "$Boost_ROOT" ] && CMAKE_ARGS+=(-D Boost_ROOT="$Boost_ROOT")

if [ -n "$OSG_MYGUI_ROOT" ] && [ -d "$OSG_MYGUI_ROOT" ]; then
    export MYGUI_HOME="$OSG_MYGUI_ROOT"
    CMAKE_ARGS+=(
        -D OPENMW_USE_SYSTEM_OSG=ON
        -D OPENMW_USE_SYSTEM_MYGUI=ON
        -D CMAKE_PREFIX_PATH="$OSG_MYGUI_ROOT"
        -D OSG_DIR="$OSG_MYGUI_ROOT"
        -D OSG_STATIC=ON
    )
    echo "Using prebuilt OSG/MyGUI from: $OSG_MYGUI_ROOT"
else
    echo "Building static OSG/MyGUI in-tree from extern/osg and extern/mygui."
    echo "OSG build mode: RelWithDebInfo with -O2 and no CPU-specific tuning."
fi

command -v ccache &>/dev/null && \
    CMAKE_ARGS+=(-D CMAKE_C_COMPILER_LAUNCHER=ccache -D CMAKE_CXX_COMPILER_LAUNCHER=ccache) && \
    echo "Using ccache."

echo ""
echo "Running CMake..."
LOG="${BUILD_DIR}/cmake.log"
cmake "${CMAKE_ARGS[@]}" "$ROOT_DIR" 2>&1 | tee "$LOG"

if [ "${PIPESTATUS[0]}" -eq 0 ]; then
    echo ""
    echo "CMake configuration succeeded. Build with:"
    echo "  cd $BUILD_DIR && make -j$NUM_JOBS"
else
    echo ""
    echo "CMake configuration failed. See $LOG"
    exit 1
fi
