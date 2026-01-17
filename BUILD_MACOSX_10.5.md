# Building OpenMW for macOS 10.5 Leopard (PowerPC)

This document describes how to build OpenMW for macOS 10.5 Leopard on PowerPC architecture.

## Prerequisites

- macOS 10.5 Leopard (or later macOS with cross-compilation setup)
- MacPorts with the following packages:
  - `gcc14` (gcc-mp-14, g++-mp-14)
  - `cmake` (3.16.0 or later)
  - `qt4` (for building Qt-based tools)
  - Dependencies: OpenSceneGraph, Bullet Physics, FFmpeg, OpenAL, SDL2, etc.

## SDK Location

The macOS 10.5 SDK should be located at:
```
/Developer/SDKs/MacOSX10.5sdk
```

If your SDK is in a different location, set the `MACOSX_SDK_PATH` environment variable:
```bash
export MACOSX_SDK_PATH="/path/to/MacOSX10.5sdk"
```

## Quick Start

### Option 1: Using the Build Script

```bash
# Full build with Qt tools (if Qt4 is available)
./CI/before_script.macos.10.5.sh

# Build without Qt tools (game engine only)
./CI/before_script.macos.10.5.sh
# (Script will auto-detect if Qt4 is missing and disable Qt tools)

# With verbose output
./CI/before_script.macos.10.5.sh -V

# With ccache
./CI/before_script.macos.10.5.sh -C
```

### Option 2: Manual CMake Configuration

```bash
mkdir build
cd build

cmake \
    -D CMAKE_BUILD_TYPE=RelWithDebInfo \
    -D CMAKE_OSX_DEPLOYMENT_TARGET=10.5 \
    -D CMAKE_OSX_ARCHITECTURES=ppc \
    -D CMAKE_OSX_SYSROOT="/Developer/SDKs/MacOSX10.5sdk" \
    -D OPENMW_MACOSX_10_5_BUILD=ON \
    -D OPENMW_POWERPC_BUILD=ON \
    -D CMAKE_C_COMPILER="gcc-mp-14" \
    -D CMAKE_CXX_COMPILER="g++-mp-14" \
    -D BUILD_LAUNCHER=OFF \
    -D BUILD_OPENCS=OFF \
    -D BUILD_WIZARD=OFF \
    -D USE_QT=FALSE \
    ..

make -j$(sysctl -n hw.ncpu)
```

### Option 3: Test Configuration First

```bash
# Test if CMake can configure the project
./test_build_10.5.sh
```

## Build Options

### Architecture Options

- `ppc` - 32-bit PowerPC (default for 10.5)
- `ppc64` - 64-bit PowerPC (if supported)

Set via:
```bash
-D CMAKE_OSX_ARCHITECTURES=ppc
# or
-D CMAKE_OSX_ARCHITECTURES=ppc64
```

### Qt Version

For macOS 10.5, Qt4 is automatically selected. If you want to explicitly control Qt:

```bash
# Force Qt4 (required for 10.5)
-D OPENMW_QT_VERSION=4

# Or disable Qt tools entirely
-D BUILD_LAUNCHER=OFF -D BUILD_OPENCS=OFF -D BUILD_WIZARD=OFF -D USE_QT=FALSE
```

### Building Specific Components

```bash
# Game engine only (no Qt)
-D BUILD_OPENMW=ON -D USE_QT=FALSE

# Tools only
-D BUILD_BSATOOL=ON -D BUILD_ESMTOOL=ON

# Everything
-D BUILD_OPENMW=ON -D BUILD_LAUNCHER=ON -D BUILD_OPENCS=ON
```

## What Was Changed

### CMakeLists.txt Modifications

1. **macOS 10.5 Detection**: Automatically detects when building for 10.5 based on deployment target
2. **PowerPC Architecture Support**: Detects PowerPC architecture and configures accordingly
3. **SDK Path Configuration**: Automatically finds macOS 10.5 SDK or uses `MACOSX_SDK_PATH`
4. **Qt4/Qt6 Compatibility**: Supports both Qt4 (for 10.5) and Qt6 (for modern macOS)
5. **C++ Standard Library**: Automatically detects if libc++ or libstdc++ should be used

### Component Updates

- `components/CMakeLists.txt`: Updated Qt linking for Qt4 compatibility
- `apps/launcher/CMakeLists.txt`: Updated Qt linking for Qt4
- `apps/opencs/CMakeLists.txt`: Updated Qt linking for Qt4
- `apps/wizard/CMakeLists.txt`: Updated Qt linking for Qt4
- `extern/osgQt/CMakeLists.txt`: Updated for Qt4 (QGLWidget vs QOpenGLWidget)

## Known Issues & Limitations

1. **Qt4 Required for Tools**: The launcher, editor, and wizard require Qt4 on macOS 10.5. If Qt4 is not available, these tools cannot be built, but the game engine can still be built.

2. **C++ Standard Library**: GCC 14 may require libc++, but macOS 10.5 predates libc++. The build system will attempt to use libc++ first, falling back to libstdc++ if needed.

3. **Dependencies**: All dependencies must be built for PowerPC architecture and macOS 10.5. Ensure all libraries are compatible.

4. **Endianness**: PowerPC is big-endian, but the codebase already has endianness handling in `components/misc/endianness.hpp`.

## Troubleshooting

### CMake Can't Find SDK

```bash
export MACOSX_SDK_PATH="/Developer/SDKs/MacOSX10.5sdk"
# or
export MACOSX_SDK_PATH="/opt/local/libexec/SDKs/MacOSX10.5.sdk"
```

### Compiler Not Found

Ensure MacPorts compilers are in PATH:
```bash
export PATH=/opt/local/bin:$PATH
which gcc-mp-14
which g++-mp-14
```

### Qt4 Not Found

Install Qt4 via MacPorts:
```bash
sudo port install qt4
```

Or disable Qt tools:
```bash
-D BUILD_LAUNCHER=OFF -D BUILD_OPENCS=OFF -D BUILD_WIZARD=OFF -D USE_QT=FALSE
```

### Linker Errors

If you get linker errors about C++ standard library:
- The build system should auto-detect, but you can manually set:
  ```bash
  -D CMAKE_CXX_FLAGS="-stdlib=libstdc++"
  ```

## Next Steps

After successful CMake configuration:

1. **Build Components**: Start with simple tools
   ```bash
   cd build
   make bsatool -j1
   ```

2. **Build Game Engine**: 
   ```bash
   make openmw -j$(sysctl -n hw.ncpu)
   ```

3. **Test**: Run the built binaries to identify runtime issues

4. **Fix Issues**: Address compilation and runtime errors as they arise

## Support

For issues specific to macOS 10.5 PowerPC builds, check:
- Build logs in `build/cmake_configure.log`
- Compilation errors in build output
- Runtime errors when testing binaries
