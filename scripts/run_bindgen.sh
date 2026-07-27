#!/usr/bin/env bash
# The spoke round trips: build tests/export/MathLib.hs as a library,
# generate bindings with `ahc bindgen`, then build and run each
# examples/ffi/<lang> program that has its toolchain installed
# (clang++ always; rustc/go/ghc when present), diffing the output.
set -eu
cd "$(dirname "$0")/.."

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

gcprefix=""
gc_ldflags=""
if gcprefix=$(brew --prefix bdw-gc 2>/dev/null) && [ -d "$gcprefix" ]; then
  gc_ldflags="-L$gcprefix/lib -lgc"
fi

scripts/ahc-build.sh --lib tests/export/MathLib.hs "$tmp/mathlib.a" \
  >/dev/null
bd="$tmp/mathlib.a.build"

fail=0
check() { # <name> <binary>
  if out=$("$2" 2>&1) \
     && [ "$out" = "$(cat "examples/ffi/$1/expected.out")" ]; then
    echo "ok   examples/ffi/$1"
  else
    echo "FAIL examples/ffi/$1"
    printf '%s\n' "$out" | head -8
    fail=1
  fi
}

# C++ (part of the base toolchain).
./bin/ahc bindgen cpp tests/export/MathLib.hs "$tmp/mathlib.a" \
  >/dev/null
# shellcheck disable=SC2086
clang++ -std=c++17 -O1 -I "$bd" -o "$tmp/cpp_main" \
  examples/ffi/cpp/main.cpp "$tmp/mathlib.a" $gc_ldflags
check cpp "$tmp/cpp_main"

# Rust.
if command -v rustc >/dev/null 2>&1; then
  ./bin/ahc bindgen rust tests/export/MathLib.hs "$tmp/mathlib.a" \
    >/dev/null
  mkdir -p "$tmp/rust"
  cp examples/ffi/rust/main.rs "$bd/ahc_exports.rs" "$tmp/rust/"
  rustflags=""
  [ -n "$gcprefix" ] && rustflags="-L $gcprefix/lib -l gc"
  # shellcheck disable=SC2086
  (cd "$tmp/rust" && rustc --edition 2021 -O main.rs \
     -C link-arg="$tmp/mathlib.a" $rustflags -o rust_main)
  check rust "$tmp/rust/rust_main"
else
  echo "skip examples/ffi/rust (no rustc)"
fi

# Go.
if command -v go >/dev/null 2>&1; then
  ./bin/ahc bindgen go tests/export/MathLib.hs "$tmp/mathlib.a" \
    >/dev/null
  mkdir -p "$tmp/go/ahc"
  cp examples/ffi/go/main.go examples/ffi/go/go.mod "$tmp/go/"
  cp "$bd/ahc.go" "$bd/ahc_exports.h" "$tmp/go/ahc/"
  cp "$tmp/mathlib.a" "$tmp/go/ahc/"
  (cd "$tmp/go" && CGO_LDFLAGS="$gc_ldflags" go build \
     -o go_main . >/dev/null 2>&1)
  check go "$tmp/go/go_main"
else
  echo "skip examples/ffi/go (no go)"
fi

# GHC: two Haskell runtimes in one process.
if command -v ghc >/dev/null 2>&1; then
  ./bin/ahc bindgen ghc tests/export/MathLib.hs "$tmp/mathlib.a" \
    >/dev/null
  mkdir -p "$tmp/ghc"
  cp examples/ffi/ghc/Main.hs "$bd/AhcLib.hs" "$tmp/ghc/"
  # shellcheck disable=SC2086
  (cd "$tmp/ghc" && ghc -O -o ghc_main Main.hs AhcLib.hs \
     "$tmp/mathlib.a" $gc_ldflags >/dev/null 2>&1)
  check ghc "$tmp/ghc/ghc_main"
else
  echo "skip examples/ffi/ghc (no ghc)"
fi

exit $fail
