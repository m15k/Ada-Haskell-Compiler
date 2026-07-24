#!/usr/bin/env bash
# Contract-discharge proofs: trivially-true claims must vanish from
# the generated C, argument-dependent ones must stay, and a
# provably-false claim must warn at compile time.
set -u
cd "$(dirname "$0")/.."
[ -x bin/ahc ] || { echo "build first: alr build --validation" >&2; exit 2; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

./bin/ahc emit tests/discharge/discharged.hs "$tmp/d" >/dev/null 2>&1
n=$(cat "$tmp/d.build"/*.c | grep -c ahc_prim_check_claim)
if [ "$n" -eq 0 ]; then echo "ok   discharged: 0 claims in C"; else
  echo "FAIL discharged: $n claims remain"; fail=1; fi

./bin/ahc emit tests/discharge/kept.hs "$tmp/k" >/dev/null 2>&1
n=$(cat "$tmp/k.build"/*.c | grep -c ahc_prim_check_claim)
if [ "$n" -gt 0 ]; then echo "ok   kept: claims present ($n)"; else
  echo "FAIL kept: claims were wrongly discharged"; fail=1; fi

./bin/ahc emit tests/discharge/never.hs "$tmp/n" >"$tmp/n.out" 2>&1
if grep -q "can never hold" "$tmp/n.out"; then
  echo "ok   never: compile-time warning emitted"; else
  echo "FAIL never: no warning"; fail=1; fi
n=$(cat "$tmp/n.build"/*.c | grep -c ahc_prim_check_claim)
if [ "$n" -gt 0 ]; then echo "ok   never: check kept ($n)"; else
  echo "FAIL never: check dropped despite False"; fail=1; fi
exit $fail
