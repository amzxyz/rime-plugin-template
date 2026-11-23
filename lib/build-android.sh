#!/usr/bin/env bash
set -euo pipefail

sdk=$1
output_dir=$2
ndk=$3
cmake_version=$4
min_sdk=$5
build_root=$6
abi=$7

lib_dir=$(cd "$(dirname "$0")" && pwd)
cmake="$sdk/cmake/$cmake_version/bin/cmake"
ninja="$sdk/cmake/$cmake_version/bin/ninja"
toolchain="$sdk/ndk/$ndk/build/cmake/android.toolchain.cmake"
jobs=${CMAKE_BUILD_PARALLEL_LEVEL:-2}
source_dir="$build_root/source"
boost="$build_root/boost_1_89_0"
archive="$lib_dir/../boost_1_89_0.tar.gz"
boost_sha=9de758db755e8330a01d995b0a24d09798048400ac25c03fc5ea9be364b13c93

if [[ ! -x "$cmake" || ! -x "$ninja" || ! -f "$toolchain" ]]; then
    echo "Install CMake $cmake_version and NDK $ndk in $sdk." >&2
    exit 1
fi
if [[ ! -f "$lib_dir/librime/plugins/lua/thirdparty/luajit/src/lua.h" ||
      ! -f "$lib_dir/evo-octagram/CMakeLists.txt" ]]; then
    echo 'Initialize sources with git submodule update --init --recursive.' >&2
    exit 1
fi

mkdir -p "$build_root" "$output_dir"
rsync -a --delete --exclude=.git "$lib_dir/librime/" "$source_dir/"
rsync -a --delete --exclude=.git "$lib_dir/evo-octagram/" "$source_dir/plugins/evo-octagram/"
git -C "$lib_dir/librime/plugins/lua/thirdparty/luajit" log -1 --format=%ct \
    > "$source_dir/plugins/lua/thirdparty/luajit/.relver"
patch -d "$source_dir" -p1 < "$lib_dir/patches/luajit-android.patch"

if [[ ! -f "$boost/boost/version.hpp" ]]; then
    if [[ ! -f "$archive" ]]; then
        curl --fail --location --retry 3 \
            https://archives.boost.io/release/1.89.0/source/boost_1_89_0.tar.gz \
            -o "$archive.part"
        mv "$archive.part" "$archive"
    fi
    checksum=$("$cmake" -E sha256sum "$archive")
    if [[ ${checksum%% *} != "$boost_sha" ]]; then
        echo "Boost archive checksum mismatch: $archive" >&2
        exit 1
    fi
    mkdir -p "$boost"
    tar -xzf "$archive" -C "$boost" --strip-components=1
fi

build_dependency() {
    local name=$1
    shift
    "$cmake" -S "$source_dir/deps/$name" -B "$abi_root/$name" \
        "${args[@]}" -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF "$@"
    "$cmake" --build "$abi_root/$name" --target install --parallel "$jobs"
}

abi_root="$build_root/$abi"
prefix="$abi_root/prefix"
args=(
    -G Ninja "-DCMAKE_MAKE_PROGRAM=$ninja"
    "-DCMAKE_TOOLCHAIN_FILE=$toolchain"
    "-DANDROID_ABI=$abi" "-DANDROID_PLATFORM=android-$min_sdk"
    -DANDROID_STL=c++_static -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DCMAKE_INSTALL_LIBDIR=lib "-DCMAKE_INSTALL_PREFIX=$prefix"
)
echo "Building librime-evo for $abi"
build_dependency leveldb -DLEVELDB_BUILD_TESTS=OFF -DLEVELDB_BUILD_BENCHMARKS=OFF
build_dependency marisa-trie -DENABLE_TOOLS=OFF
build_dependency yaml-cpp -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF

RIME_PLUGINS=amzxyz/librime-evo-octagram \
    "$cmake" -S "$source_dir" -B "$abi_root/librime" "${args[@]}" \
    "-DCMAKE_PREFIX_PATH=$prefix" \
    "-DLevelDb_INCLUDE_PATH=$prefix/include" "-DLevelDb_LIBRARY=$prefix/lib/libleveldb.a" \
    "-DMarisa_INCLUDE_PATH=$prefix/include" "-DMarisa_LIBRARY=$prefix/lib/libmarisa.a" \
    "-DYamlCpp_INCLUDE_PATH=$prefix/include" "-DYamlCpp_NEW_API=$prefix/include" \
    "-DYamlCpp_LIBRARY=$prefix/lib/libyaml-cpp.a" \
    -DCMAKE_CXX_FLAGS=-DBOOST_ALL_NO_EMBEDDED_GDB_SCRIPTS \
    "-DBoost_INCLUDE_DIR=$boost" -DBoost_NO_BOOST_CMAKE=ON -DBoost_NO_SYSTEM_PATHS=ON \
    -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC=ON -DBUILD_TEST=OFF -DBUILD_TOOLS=OFF \
    -DBUILD_MERGED_PLUGINS=ON -DBUILD_SEPARATE_LIBS=OFF
RIME_PLUGINS=amzxyz/librime-evo-octagram \
    "$cmake" --build "$abi_root/librime" --target rime --parallel "$jobs"
nm="$sdk/ndk/$ndk/toolchains/llvm/prebuilt"
prebuilt=( "$nm"/* )
binary="$abi_root/librime/lib/librime.so"
"${prebuilt[0]}/bin/llvm-nm" --dynamic --defined-only --demangle "$binary" |
    awk '
        / T rime_get_api$/ { api = 1 }
        / T rime_require_module_lua\(\)$/ { lua = 1 }
        / T rime_require_module_octagram\(\)$/ { octagram = 1 }
        / T luaJIT_setmode$/ { jit = 1 }
        END {
            if (!(api && lua && octagram && jit)) {
                print "Missing Rime API, LuaJIT, Lua or Octagram symbols" > "/dev/stderr"
                exit 1
            }
        }
    '
mkdir -p "$output_dir/$abi"
cp "$binary" "$output_dir/$abi/librime.so"
