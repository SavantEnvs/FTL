#!/usr/bin/env bash
#
# mayhem/test.sh — RUN FTL's own standalone regression binaries (built by mayhem/build.sh into cmake_ci/).
# exit 0 = pass. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
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


# Upstream ships four standalone regression programs (test/*_regression.c) that its bats suite runs.
# Each prints its own verdicts; parse those (a neutered binary prints nothing, so the expected counts
# below are not met and the suite fails).
B="$SRC/cmake_ci"
passed=0 ; failed=0

run_bin() {   # run_bin <name> ; sets OUT
  local bin="$B/$1"
  if [ ! -x "$bin" ]; then echo "missing $bin — mayhem/build.sh should have built it" >&2 ; failed=$((failed+1)); OUT="" ; return 1 ; fi
  OUT="$(cd "$B" && timeout 300 "$bin" 2>&1)" || { echo "$1 exited non-zero" >&2 ; failed=$((failed+1)) ; return 1 ; }
}

expect_count() {   # expect_count <label> <regex> <want>
  local label="$1" re="$2" want="$3" got
  got="$(printf '%s\n' "$OUT" | grep -cE "$re" || true)"
  if [ "$got" -eq "$want" ]; then passed=$((passed+1)); else
    echo "$label: expected $want match(es) of /$re/, got $got" >&2 ; failed=$((failed+1)) ; fi
}

# tar parser: 12 named cases, each "PASS <name>"
if run_bin tar_regression; then expect_count "tar_regression PASS lines" '^PASS ' 12; expect_count "tar_regression FAIL lines" 'FAIL' 0 ; fi
# gzip parser: 9 named cases
if run_bin gzip_regression; then expect_count "gzip_regression PASS lines" '^PASS ' 9; expect_count "gzip_regression FAIL lines" 'FAIL' 0 ; fi
# PTR resolver against a scripted stale-response server
if run_bin ptr_response_regression; then
  for m in HOSTNAME_WARNING_POSITION FIRST_LOOKUP_TIMEOUT SERVER_SEQUENCE PTR_RESPONSE_REGRESSION; do
    expect_count "ptr_response_regression $m" "^$m=PASS\$" 1
  done
  expect_count "ptr_response_regression second lookup answer" '^SECOND_LOOKUP_RESULT=answer-b\.example$' 1
fi
# TXT stat buffer bookkeeping (GHSA-8fc6-q9x4-892v)
if run_bin txt_stat_regression; then
  expect_count "txt_stat_regression verdict" '^TXT_STAT_SERVERS_REGRESSION=PASS$' 1
  expect_count "txt_stat_regression sizes" '^TXT_STAT_SERVERS \((1st|2nd)\): 1280 bytes$' 2
fi

emit_ctrf "ftl-regression" "$passed" "$failed" 0
