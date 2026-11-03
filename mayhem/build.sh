#!/usr/bin/env bash
#
# mayhem/build.sh — build the Hercules fuzz harnesses, their standalone reproducers, and the
# project's own unit tests (run by mayhem/test.sh).
#
# Hercules' real build is CMake + conan (network). That is not usable offline, so the sources the
# harnesses and tests need (src/common, 3rdparty/libconfig, mt19937ar, http-parser) are compiled
# directly with clang. Build state lives in mayhem/.build (gitignored, wiped and rebuilt every run).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE STANDALONE_FUZZ_MAIN MAYHEM_JOBS COVERAGE_FLAGS

: "${SRC:=/mayhem}"
cd "$SRC"

B="$SRC/mayhem/.build"
H="$SRC/mayhem/harnesses"
rm -rf "$B"
mkdir -p "$B/autogen" "$B/fuzz" "$B/norm" "$B/tests"

sh sysinfogen.sh "$B/autogen/sysinfo.inc.new" "$B/autogen/sysinfo.inc" "$CC" >/dev/null

DEFS="-DHAS_TLS -DHAVE_MONOTONIC_CLOCK -DUSE_HTTP_PARSER -DNO_MEMMGR"
INCS="-I$SRC/src -I$SRC/3rdparty -I$SRC/3rdparty/http-parser -I$B/autogen -I/usr/include/mariadb -I/usr/include/mariadb/mysql"
CF="-fno-strict-aliasing -fsigned-char -pipe -w"
# Fuzz objects: sanitized, DWARF<=3, and SanCov-instrumented so the fuzzed library reports coverage.
FUZZ_CF="$CF $DEFS -DSANITIZE $INCS $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
NORM_CF="$CF $DEFS $INCS -O2 $COVERAGE_FLAGS"

# compile <fuzz|norm> <src> <obj>
compile() {
	local kind=$1 src=$2 obj=$3 flags lang
	case "$src" in *.cpp|*.cc) lang="$CXX -std=c++20" ;; *) lang="$CC -std=gnu11" ;; esac
	if [ "$kind" = fuzz ]; then flags=$FUZZ_CF; else flags=$NORM_CF; fi
	# flex's fatal-error handler exits; abort instead so libFuzzer reports a crash rather than "fuzz target exited".
	if [ "$kind" = fuzz ] && [ "$src" = 3rdparty/libconfig/scanner.c ]; then
		flags="$flags -DYY_FATAL_ERROR(msg)=(fputs(msg,stderr),abort())"
	fi
	# shellcheck disable=SC2086
	$lang $flags -c "$src" -o "$obj"
}
export -f compile
export FUZZ_CF NORM_CF

LIB_SRCS=(src/common/*.cpp)
LIB_SRCS+=(3rdparty/libconfig/grammar.c 3rdparty/libconfig/libconfig.c 3rdparty/libconfig/scanctx.c
           3rdparty/libconfig/scanner.c 3rdparty/libconfig/strbuf.c 3rdparty/mt19937ar/mt19937ar.c
           3rdparty/http-parser/http_parser.c)

jobs=()
for kind in fuzz norm; do
	for s in "${LIB_SRCS[@]}"; do
		d=$(dirname "$s" | tr / _)
		jobs+=("$kind $s $B/$kind/${d}_$(basename "$s").o")
	done
done
# Fuzz harness TUs and the shared core bring-up TU.
jobs+=("fuzz $H/herc_init.cpp $B/fuzz/herc_init.o")
for h in libconfig strlib grfio; do jobs+=("fuzz $H/fuzz_$h.cpp $B/fuzz/fuzz_$h.o"); done
for h in http_parser http_url; do jobs+=("fuzz $H/fuzz_$h.c $B/fuzz/fuzz_$h.o"); done
printf '%s\n' "${jobs[@]}" | xargs -P "$MAYHEM_JOBS" -L1 bash -c 'compile "$@"' _

# The core TU is linked from herc_init.o (it needs core_defaults), so drop the plain core object.
rm -f "$B/fuzz/src_common_core.cpp.o"
# grfio harness #includes grfio.cpp itself, so it must not also pull the archive copy.
ar rcs "$B/libfuzz.a" "$B"/fuzz/src_common_*.o "$B"/fuzz/3rdparty_*.o
ar rcs "$B/libnorm.a" "$B"/norm/*.o

# lsan off hook + standalone driver objects.
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/lsan_off.o"
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"
# shellcheck disable=SC2086
$CC $DEBUG_FLAGS -c "$SRC/mayhem/cov_stubs.c" -o "$B/cov_stubs.o"

SYSLIBS="-lmariadb -lz -lpthread -ldl -lm"
for h in libconfig strlib grfio; do
	# shellcheck disable=SC2086
	$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$B/fuzz/fuzz_$h.o" "$B/fuzz/herc_init.o" "$B/libfuzz.a" \
		"$B/lsan_off.o" $SYSLIBS -o "/mayhem/fuzz_$h"
	# shellcheck disable=SC2086
	$CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$B/fuzz/fuzz_$h.o" "$B/fuzz/herc_init.o" "$B/standalone_main.o" "$B/cov_stubs.o" \
		"$B/libfuzz.a" "$B/lsan_off.o" $SYSLIBS -o "/mayhem/fuzz_$h-standalone"
done
for h in http_parser http_url; do
	# shellcheck disable=SC2086
	$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$B/fuzz/fuzz_$h.o" "$B/fuzz/3rdparty_http-parser_http_parser.c.o" \
		"$B/lsan_off.o" -lstdc++ -o "/mayhem/fuzz_$h"
	# shellcheck disable=SC2086
	$CC $SANITIZER_FLAGS $DEBUG_FLAGS "$B/fuzz/fuzz_$h.o" "$B/fuzz/3rdparty_http-parser_http_parser.c.o" \
		"$B/standalone_main.o" "$B/cov_stubs.o" "$B/lsan_off.o" -lstdc++ -o "/mayhem/fuzz_$h-standalone"
done

# Unit tests with the project's NORMAL flags (no sanitizers) — mayhem/test.sh only runs these.
for t in base62 chunked libconfig; do
	# shellcheck disable=SC2086
	$CXX -std=c++20 $NORM_CF "src/test/test_$t.cpp" "$B/libnorm.a" $SYSLIBS -o "$B/tests/test_$t"
done
# shellcheck disable=SC2086
$CC -std=gnu11 -O2 -w $COVERAGE_FLAGS 3rdparty/http-parser/test.c 3rdparty/http-parser/http_parser.c \
	-I3rdparty/http-parser -o "$B/tests/http_parser_test"
