#!/usr/bin/env bash
set -ex

# Build and install libblake3 (not yet packaged in conda-forge)
# Use the Ninja generator: the build env provides ninja, not make, so the
# default "Unix Makefiles" generator fails to find CMAKE_MAKE_PROGRAM.
cmake -S "${SRC_DIR}/blake3/c" -B blake3-build \
    -GNinja \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DBLAKE3_BUILD_SHARED=ON \
    -DBLAKE3_BUILD_TESTING=OFF
cmake --build blake3-build --parallel "${CPU_COUNT}"
cmake --install blake3-build

# nix's libutil/meson.build uses method:'system' for boost, which requires BOOST_ROOT
export BOOST_ROOT="${PREFIX}"

# On glibc <2.34, dlopen lives in libdl.so (not libc.so); nix uses dlopen in globals.cc
export LDFLAGS="${LDFLAGS} -ldl"

# nix 2.34+ explicitly forbids -DNDEBUG (util.cc has a hard #error check) because
# it relies on assert() as a reachability guard in switch default: cases
export CPPFLAGS="${CPPFLAGS//-DNDEBUG/}"

# nix sets -Werror=return-type; without -DNDEBUG the assert() guards remain but
# some constexpr switch defaults still warn — keep as warning-only
export CXXFLAGS="${CXXFLAGS} -Wno-error=return-type"

# Build nix with Meson
meson setup builddir \
    --prefix="${PREFIX}" \
    --libdir=lib \
    --buildtype=release \
    -Dunit-tests=false \
    -Dbindings=false \
    -Ddoc-gen=false \
    -Dbenchmarks=false \
    -Djson-schema-checks=false

ninja -C builddir -j "${CPU_COUNT}"
ninja -C builddir install
