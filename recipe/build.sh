#!/usr/bin/env bash
set -ex

if [[ "$(uname)" == 'Darwin' ]]; then
  export CXXFLAGS="$CXXFLAGS -std=c++17"
fi

# GCC 14 emits -Wmaybe-uninitialized for boost coroutine2 headers; suppress as error
export CXXFLAGS="${CXXFLAGS} -Wno-error=maybe-uninitialized"

./configure --prefix=${PREFIX}
make -j ${CPU_COUNT}
make check
make install
