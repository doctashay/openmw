#!/bin/bash -e

# macOS 10.5 Leopard PowerPC Build Script
# Assumes all tools available via MacPorts

set -e

VERBOSE=""
USE_CCACHE=""
KEEP=""
USE_WERROR=""

while [ $# -gt 0 ]; do
	ARGSTR=$1
	shift

	if [ ${ARGSTR:0:1} != "-" ]; then
		echo "Unknown argument $ARGSTR"
		echo "Try '$0 -h'"
		exit 1
	fi

	for (( i=1; i<${#ARGSTR}; i++ )); do
		ARG=${ARGSTR:$i:1}
		case $ARG in
			V )
				VERBOSE=true ;;
			C )
				USE_CCACHE=true ;;
			k )
				KEEP=true ;;
			E )
				USE_WERROR=true ;;
			h )
				cat <<EOF
Usage: $0 [-VCkEh]
Options:
	-C	Use ccache
	-h	Show this message
	-k	Keep the old build directory
	-V	Run verbosely
	-E	Use warnings as errors (-Werror)
EOF
				exit 0
				;;
			* )
				echo "Unknown argument $ARG."
				echo "Try '$0 -h'"
				exit 1 ;;
		esac
	done
done

# Configuration
BUILD_DIR="${BUILD_DIR:-build}"
DEPLOYMENT_TARGET="10.5"
ARCHITECTURE="${ARCHITECTURE:-ppc}"  # or "ppc64" for 64-bit PowerPC
SDK_PATH="/Developer/SDKs/MacOSX10.5sdk"

# Verify SDK exists
if [ ! -d "$SDK_PATH" ]; then
    echo "ERROR: macOS 10.5 SDK not found at: $SDK_PATH"
    echo "Please verify the SDK path or set MACOSX_SDK_PATH environment variable"
    exit 1
fi

echo "=== macOS 10.5 PowerPC Build Configuration ==="
echo "SDK Path: $SDK_PATH"
echo "Deployment Target: $DEPLOYMENT_TARGET"
echo "Architecture: $ARCHITECTURE"
echo ""

# Verify compilers
if ! command -v gcc-mp-14 >/dev/null 2>&1; then
    echo "ERROR: gcc-mp-14 not found. Please install via MacPorts"
    exit 1
fi

if ! command -v g++-mp-14 >/dev/null 2>&1; then
    echo "ERROR: g++-mp-14 not found. Please install via MacPorts"
    exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "ERROR: cmake not found. Please install via MacPorts"
    exit 1
fi

echo "Using compilers:"
gcc-mp-14 --version | head -1
g++-mp-14 --version | head -1
cmake --version | head -1
echo ""

# Find Qt4 (required for 10.5)
QT_PATH=""
if command -v qmake-qt4 >/dev/null 2>&1; then
    QT_PATH=$(qmake-qt4 -v 2>&1 | sed -rn -e 's/Using Qt version [.0-9]+ in //p')
elif command -v qmake >/dev/null 2>&1; then
    QT_VERSION=$(qmake -v 2>&1 | grep -o "Qt version [0-9]" | grep -o "[0-9]" || echo "")
    if [ "$QT_VERSION" = "4" ]; then
        QT_PATH=$(qmake -v 2>&1 | sed -rn -e 's/Using Qt version [.0-9]+ in //p')
    fi
fi

if [ -z "$QT_PATH" ]; then
    echo "WARNING: Qt4 not found. Qt-based tools (launcher, editor, wizard) will not build."
    echo "The game engine can still be built without Qt."
    BUILD_QT_TOOLS="OFF"
else
    echo "Found Qt4 at: $QT_PATH"
    BUILD_QT_TOOLS="ON"
fi
echo ""

# Find dependencies via pkg-config or MacPorts
ICU_PATH=$(pkg-config --variable=prefix icu-i18n 2>/dev/null || pkg-config --variable=prefix icu-uc 2>/dev/null || echo "/opt/local")
OPENAL_PATH=$(pkg-config --variable=prefix openal 2>/dev/null || echo "/opt/local")

echo "Dependencies:"
echo "  ICU path: $ICU_PATH"
echo "  OpenAL path: $OPENAL_PATH"
echo ""

# Create build directory
if [[ -z $KEEP ]]; then
    if [[ -n $VERBOSE && -d "$BUILD_DIR" ]]; then
        echo "Deleting existing build directory"
    fi
    rm -fr "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# CMake configuration
declare -a CMAKE_ARGS=(
    -D CMAKE_BUILD_TYPE=RelWithDebInfo
    -D CMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
    -D CMAKE_OSX_ARCHITECTURES="$ARCHITECTURE"
    -D CMAKE_OSX_SYSROOT="$SDK_PATH"
    -D OPENMW_MACOSX_10_5_BUILD=ON
    -D OPENMW_POWERPC_BUILD=ON
    -D CMAKE_C_COMPILER="gcc-mp-14"
    -D CMAKE_CXX_COMPILER="g++-mp-14"
    -D CMAKE_CXX_FLAGS="-mmacosx-version-min=$DEPLOYMENT_TARGET"
    -D CMAKE_C_FLAGS="-mmacosx-version-min=$DEPLOYMENT_TARGET"
)

# Add Qt4 if found
if [ "$BUILD_QT_TOOLS" = "ON" ] && [ -n "$QT_PATH" ]; then
    CMAKE_ARGS+=(
        -D CMAKE_PREFIX_PATH="$QT_PATH"
        -D OPENMW_QT_VERSION=4
        -D BUILD_LAUNCHER=ON
        -D BUILD_OPENCS=ON
        -D BUILD_WIZARD=ON
    )
else
    # Disable Qt-based tools
    CMAKE_ARGS+=(
        -D BUILD_LAUNCHER=OFF
        -D BUILD_OPENCS=OFF
        -D BUILD_WIZARD=OFF
        -D USE_QT=FALSE
    )
fi

# Add other dependencies
CMAKE_ARGS+=(
    -D ICU_ROOT="$ICU_PATH"
    -D OPENAL_ROOT="$OPENAL_PATH"
    -D OPENMW_USE_SYSTEM_BULLET=ON
    -D OPENMW_USE_SYSTEM_OSG=ON
    -D OPENMW_USE_SYSTEM_MYGUI=ON
    -D OPENMW_USE_SYSTEM_ICU=ON
    -D OPENMW_USE_SYSTEM_YAML_CPP=ON
    -D OPENMW_USE_SYSTEM_RECASTNAVIGATION=ON
)

# Build options
CMAKE_ARGS+=(
    -D BUILD_OPENMW=ON
    -D BUILD_ESMTOOL=ON
    -D BUILD_BSATOOL=ON
    -D BUILD_ESSIMPORTER=ON
    -D BUILD_NIFTEST=ON
    -D BUILD_NAVMESHTOOL=ON
    -D BUILD_BULLETOBJECTTOOL=ON
)

if [[ -n $USE_CCACHE ]]; then
    CMAKE_ARGS+=(
        -D CMAKE_C_COMPILER_LAUNCHER="ccache"
        -D CMAKE_CXX_COMPILER_LAUNCHER="ccache"
    )
fi

if [[ -n $USE_WERROR ]]; then
    CMAKE_ARGS+=(
        -D OPENMW_CXX_FLAGS="-Werror"
    )
fi

# Print configuration
if [[ -n $VERBOSE ]]; then
    echo "=== CMake Configuration Arguments ==="
    printf '  %s\n' "${CMAKE_ARGS[@]}"
    echo ""
fi

# Run CMake
echo "Running CMake configuration..."
export MACOSX_SDK_PATH="$SDK_PATH"
cmake "${CMAKE_ARGS[@]}" .. 2>&1 | tee cmake_configure.log

CMAKE_EXIT_CODE=${PIPESTATUS[0]}

if [ $CMAKE_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=== CMake Configuration Successful ==="
    echo "Next steps:"
    echo "1. Review cmake_configure.log for any warnings"
    echo "2. Run: cd $BUILD_DIR && make -j\$(sysctl -n hw.ncpu)"
    echo "3. Check build output for compilation errors"
else
    echo ""
    echo "=== CMake Configuration Failed ==="
    echo "Check cmake_configure.log for details"
    exit $CMAKE_EXIT_CODE
fi
