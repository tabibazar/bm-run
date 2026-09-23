#!/usr/bin/env bash
# tests/run.sh -- run bm against BareMetal Cloud and check every outcome.
# Needs BM_API_KEY and a finished 'bm setup'. Uses one instance at a time and
# cleans up after itself. About eleven minutes.
set -uo pipefail
cd "$(dirname "$0")/.."
pass=0; fail=0; LOG=$(mktemp -d)
check() {  # name expected-rc command... ; then patterns that must appear
	local name=$1 want=$2; shift 2
	local pats=(); while [ "$1" != "--" ]; do pats+=("$1"); shift; done; shift
	"$@" > "$LOG/$name" 2>&1; local rc=$?
	local ok=1; [ "$rc" = "$want" ] || ok=0
	for p in "${pats[@]}"; do grep -qF -- "$p" "$LOG/$name" || { ok=0; echo "    missing: $p"; }; done
	if [ $ok = 1 ]; then pass=$((pass+1)); echo "PASS  $name"; else fail=$((fail+1)); echo "FAIL  $name (rc=$rc, want $want)"; sed 's/^/    | /' "$LOG/$name" | tail -15; fi
}
V="verified: the machine booted exactly the image built here"
check hello      0 "Hello from a machine with no operating system." "$V" "cleaned up" -- ./bm run examples/hello.c
check primes     0 "primes below 10000000: 664579" "correct: that is the known value" "$V" -- ./bm run examples/primes.c
check https      0 "over verified TLS: HTTP 200" "page title: Example Domain" "$V" -- ./bm run --timeout 90 examples/https.c
check machine    0 "processor:" "memory:" "When main() returns, this machine stops." "$V" -- ./bm run examples/machine.c
check mandelbrot 0 "@@@@@@@@@@" "$V" -- ./bm run examples/mandelbrot.c
check life       0 "correct: the glider moved exactly 10 squares" "$V" -- ./bm run examples/life.c
check pi         0 "correct: the first 100 decimals match" "$V" -- ./bm run examples/pi.c
check collatz    0 "correct: that is the known answer" "$V" -- ./bm run examples/collatz.c
check threads    0 "correct: the total is n(n+1)/2" "$V" -- ./bm run examples/threads.c
check database   0 "correct: the ratio is 1 for every planet" "$V" -- ./bm run examples/database.c
check crypto     0 "matches the published test vector" "\"Pay Alice 90 dollars\"  rejected" "$V" -- ./bm run examples/crypto.c
check github     0 "asked api.github.com about ReturnInfinity/BareMetal" "$V" -- ./bm run --timeout 90 examples/github.c
check facts      0 "after 2026-01-01, plausible" "rdrand: works" "malloc 8 MiB: works" "facts ok" "$V" -- ./bm run tests/facts.c
check multifile  0 "two files linked: 40 + 2 = 42" "$V" -- ./bm run tests/multi/main.c tests/multi/add.c
check compile    1 "tests/bad.c:1:25: error" "build failed" -- ./bm run tests/bad.c
check missing    1 "tests/nope.c not found" -- ./bm run tests/nope.c
check nokey      1 "BM_API_KEY is not set" -- env BM_API_KEY= ./bm run examples/hello.c
check timeout    3 "about to loop forever" "did not return within 20 s" "cleaned up" -- ./bm run --timeout 20 tests/forever.c
check crash      4 "about to write through a null pointer" "Exception" "may have crashed" "cleaned up" -- ./bm run tests/crash.c
check bigoutput  0 "END OF OUTPUT" "only its end is shown" "$V" -- ./bm run --timeout 300 tests/bigout.c
leftover=$(./bm ls | grep -c 'bm-' || true)
[ "$leftover" = 0 ] && { pass=$((pass+1)); echo "PASS  nothing left on the account"; } || { fail=$((fail+1)); echo "FAIL  $leftover bm-* items left on the account"; }
echo "$pass passed, $fail failed"; [ $fail = 0 ]
