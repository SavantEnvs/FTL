#!/usr/bin/env bash
#
# mayhem/build.sh — build Pi-hole FTL's fuzz harnesses and its regression-test oracle.
#
# Runs in the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem; offline-safe (every dependency
# is an apt -dev package baked into the image).
#   cmake/     sanitized + SanCov build of the whole project (gitignored upstream)
#   cmake_ci/  normal-flags build of upstream's regression binaries, which mayhem/test.sh runs
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# --- 1) The project itself, sanitized and SanCov-instrumented -----------------------------------
# Debian trixie's mbedTLS 3.6 no longer matches src/webserver/x509.c; the fuzzed parsers do not use TLS.
FUZZ_CFLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
cmake -S . -B cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_C_FLAGS="$FUZZ_CFLAGS" \
    -DUSE_MBED_TLS=OFF
cmake --build cmake --target pihole-FTL -j"$MAYHEM_JOBS"

# Link every project object into the harnesses except main(): rename it so the harness's own
# libFuzzer entry point is the only one.
OBJ_DIR=cmake/src
objcopy --redefine-sym main=ftl_main "$OBJ_DIR/CMakeFiles/core.dir/main.c.o" cmake/ftl_main.o
mapfile -t OBJS < <(find "$OBJ_DIR" -name '*.o' -path '*CMakeFiles/*.dir/*' ! -path '*/core.dir/main.c.o' | sort)
# Libraries exactly as upstream links pihole-FTL (everything after "-o <exe>")
read -r -a LIBS <<< "$(sed -E 's/.* -o [^ ]+ //' "$OBJ_DIR/CMakeFiles/pihole-FTL.dir/link.txt")"

# --- 2) Harnesses: fuzzer binary + standalone reproducer each -----------------------------------
HARNESS_CFLAGS=(-std=gnu17 -O1 -D_FILE_OFFSET_BITS=64 -DHAVE_POLL_H '-DDNSMASQ_VERSION="fuzz"'
                -I"$SRC/src" -I"$SRC/src/dnsmasq")
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o cmake/lsan_off.o
$CC -x c $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o cmake/standalone_main.o

TARGETS=(fuzz_tar fuzz_gzip fuzz_dhcp_leases fuzz_regex fuzz_parselist fuzz_toml fuzz_dns_packet)
for t in "${TARGETS[@]}"; do
    $CC $FUZZ_CFLAGS "${HARNESS_CFLAGS[@]}" -c "$SRC/mayhem/$t.c" -o "cmake/$t.o"
    $CC $FUZZ_CFLAGS $LIB_FUZZING_ENGINE "cmake/$t.o" cmake/ftl_main.o "${OBJS[@]}" cmake/lsan_off.o \
        "${LIBS[@]}" -o "$SRC/$t"
    $CC $FUZZ_CFLAGS "cmake/$t.o" cmake/standalone_main.o cmake/ftl_main.o "${OBJS[@]}" cmake/lsan_off.o \
        "${LIBS[@]}" -o "$SRC/$t-standalone"
done

# --- 3) Upstream's regression binaries, with the project's NORMAL flags -------------------------
env -u CFLAGS -u CXXFLAGS -u LDFLAGS cmake -S . -B cmake_ci \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" \
    -DUSE_MBED_TLS=OFF \
    -DBUILD_TAR_REGRESSION=ON -DBUILD_GZIP_REGRESSION=ON \
    -DBUILD_PTR_RESPONSE_REGRESSION=ON -DBUILD_TXT_STAT_REGRESSION=ON
cmake --build cmake_ci -j"$MAYHEM_JOBS" \
    --target tar_regression gzip_regression ptr_response_regression txt_stat_regression
