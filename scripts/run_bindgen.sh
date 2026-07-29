#!/usr/bin/env bash
# The spoke round trips: build examples/ffi/engine/Engine.hs as a
# library, generate bindings with `ahc bindgen`, then build and run
# each examples/ffi/<lang> program that has its toolchain installed
# (clang/clang++ always; rustc/go/ghc when present), diffing output.
#
# Every host also DEFINES host_log, the C-ABI symbol Engine.hs
# imports - so each example exercises both directions at once.
set -eu
cd "$(dirname "$0")/.."

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

gcprefix=""
gc_ldflags=""
if gcprefix=$(brew --prefix bdw-gc 2>/dev/null) && [ -d "$gcprefix" ]; then
  gc_ldflags="-L$gcprefix/lib -lgc"
fi

src=examples/ffi/engine/Engine.hs
lib="$tmp/engine.a"
scripts/ahc-build.sh --lib "$src" "$lib" >/dev/null 2>&1
bd="$tmp/engine.a.build"

fail=0
check() { # <name> <binary>
  if out=$("$2" 2>&1) \
     && [ "$out" = "$(cat "examples/ffi/$1/expected.out")" ]; then
    echo "ok   examples/ffi/$1"
  else
    echo "FAIL examples/ffi/$1"
    printf '%s\n' "$out" | head -12
    fail=1
  fi
}

# C: the generated ahc_exports.h *is* the binding - no bindgen step.
# shellcheck disable=SC2086
clang -O1 -I "$bd" -o "$tmp/c_main" examples/ffi/c/main.c "$lib" \
  $gc_ldflags
check c "$tmp/c_main"

# C++ (part of the base toolchain).
./bin/ahc bindgen cpp "$src" "$lib" >/dev/null
# shellcheck disable=SC2086
clang++ -std=c++17 -O1 -I "$bd" -o "$tmp/cpp_main" \
  examples/ffi/cpp/main.cpp "$lib" $gc_ldflags
check cpp "$tmp/cpp_main"

# Rust.
if command -v rustc >/dev/null 2>&1; then
  ./bin/ahc bindgen rust "$src" "$lib" >/dev/null
  mkdir -p "$tmp/rust"
  cp examples/ffi/rust/main.rs "$bd/ahc_exports.rs" "$tmp/rust/"
  rustflags=""
  [ -n "$gcprefix" ] && rustflags="-L $gcprefix/lib -l gc"
  # shellcheck disable=SC2086
  (cd "$tmp/rust" && rustc --edition 2021 -O main.rs \
     -C link-arg="$lib" $rustflags -o rust_main)
  check rust "$tmp/rust/rust_main"
else
  echo "skip examples/ffi/rust (no rustc)"
fi

# Go.
if command -v go >/dev/null 2>&1; then
  ./bin/ahc bindgen go "$src" "$lib" >/dev/null
  mkdir -p "$tmp/go/ahc"
  cp examples/ffi/go/main.go examples/ffi/go/go.mod "$tmp/go/"
  cp "$bd/ahc.go" "$bd/ahc_exports.h" "$lib" "$tmp/go/ahc/"
  (cd "$tmp/go" && CGO_LDFLAGS="$gc_ldflags" go build \
     -o go_main . >/dev/null 2>&1)
  check go "$tmp/go/go_main"
else
  echo "skip examples/ffi/go (no go)"
fi

# GHC: two Haskell runtimes in one process, calling each other.
if command -v ghc >/dev/null 2>&1; then
  ./bin/ahc bindgen ghc "$src" "$lib" >/dev/null
  mkdir -p "$tmp/ghc"
  cp examples/ffi/ghc/Main.hs "$bd/AhcLib.hs" "$tmp/ghc/"
  # shellcheck disable=SC2086
  (cd "$tmp/ghc" && ghc -O -o ghc_main Main.hs AhcLib.hs \
     "$lib" $gc_ldflags >/dev/null 2>&1)
  check ghc "$tmp/ghc/ghc_main"
else
  echo "skip examples/ffi/ghc (no ghc)"
fi

exit $fail
