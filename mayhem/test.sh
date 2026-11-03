#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the upstream unit tests built by mayhem/build.sh (Hercules src/test/test_*.cpp
# plus the bundled http-parser test.c; the spinlock stress test is skipped — minutes of CPU spinning). A test passes only if it exits 0 AND prints its own
# known-answer success markers the expected number of times, so a no-op/exit(0) program fails.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

B="$SRC/mayhem/.build/tests"
passed=0; failed=0

# run_suite <name> <binary> <marker-regex> <expected-marker-count>
# The marker lines are printed by the test itself after it asserted its expected values.
run_suite() {
  local name="$1" bin="$2" marker="$3" want="$4" out got rc
  if [ ! -x "$bin" ]; then
    echo "FAIL $name: $bin missing (mayhem/build.sh should have built it)" >&2
    failed=$((failed + 1)); return
  fi
  out=$("$bin" 2>&1); rc=$?
  got=$(printf '%s\n' "$out" | grep -ac -- "$marker")
  if [ "$rc" -eq 0 ] && [ "$got" -eq "$want" ]; then
    echo "PASS $name"
    passed=$((passed + 1))
  else
    echo "FAIL $name: rc=$rc, '$marker' seen $got times (expected $want)" >&2
    printf '%s\n' "$out" | tail -n 15 >&2
    failed=$((failed + 1))
  fi
}

run_suite base62        "$B/test_base62"        'Test passed\.'                                       1
run_suite base62-final  "$B/test_base62"        'All tests passed\.'                                  1
run_suite libconfig     "$B/test_libconfig"     '\[Info\]: Test passed\.'                             17
run_suite libconfig-all "$B/test_libconfig"     'All tests passed\.'                                  1
run_suite chunked       "$B/test_chunked"       'Tests passed\.'                                      1
run_suite http-parser-responses "$B/http_parser_test" '^responses okay$'                              1
run_suite http-parser-requests  "$B/http_parser_test" '^requests okay$'                               1

emit_ctrf "hercules-unit" "$passed" "$failed" 0
