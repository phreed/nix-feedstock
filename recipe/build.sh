#!/usr/bin/env bash
set -ex

# Build and install libblake3 (not yet packaged in conda-forge)
# These are cross-compiled builds (e.g. linux-aarch64/ppc64le build on linux-64,
# osx-arm64 on osx-64), so BLAKE3's SIMD auto-detection reads the x86_64 *build
# host* and wrongly selects "amd64-asm" for every target. That ships a
# hand-written x86 .S file the assembler rejects on non-x86 targets (and even on
# x86 the conda assembler rejects it). Set BLAKE3_SIMD_TYPE explicitly per the
# *target* arch so we never rely on the broken auto-detection.
case "${target_platform}" in
    linux-64 | osx-64)
        blake3_simd_type="x86-intrinsics"
        ;;
    linux-aarch64 | osx-arm64)
        blake3_simd_type="neon-intrinsics"
        ;;
    *)
        # ppc64le and any other arch: no SIMD acceleration, portable C only.
        blake3_simd_type="none"
        ;;
esac

# Use the Ninja generator: the build env provides ninja, not make, so the
# default "Unix Makefiles" generator fails to find CMAKE_MAKE_PROGRAM.
# ${CMAKE_ARGS} carries conda's cross-compilation settings (sysroot, deployment
# target, CMAKE_SYSTEM_NAME/PROCESSOR, cross ar/ranlib/ld). It is required for
# the osx-64 -> osx-arm64 cross build, where the compiler alone doesn't tell
# CMake the target arch and sysroot the way a GCC cross-compiler does on Linux.
cmake -S "${SRC_DIR}/blake3/c" -B blake3-build \
    ${CMAKE_ARGS} \
    -GNinja \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DBLAKE3_BUILD_SHARED=ON \
    -DBLAKE3_BUILD_TESTING=OFF \
    -DBLAKE3_SIMD_TYPE="${blake3_simd_type}"
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

# Build nix with Meson.
# ${MESON_ARGS} carries conda's --prefix/--libdir/--buildtype and, crucially for
# cross builds, --cross-file. Without it Meson treats an osx-64 -> osx-arm64
# build as native, compiles its sanity-check probe for arm64, then fails trying
# to run that binary on the x86_64 build host ("Bad CPU type in executable").
# Do not re-pass --prefix/--libdir/--buildtype here: MESON_ARGS already sets
# them, and specifying an option twice makes Meson error.
meson setup builddir \
    ${MESON_ARGS} \
    -Dunit-tests=false \
    -Dbindings=false \
    -Ddoc-gen=false \
    -Dbenchmarks=false \
    -Djson-schema-checks=false

ninja -C builddir -j "${CPU_COUNT}"
ninja -C builddir install
