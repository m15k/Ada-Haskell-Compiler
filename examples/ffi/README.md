# The spokes: one Haskell library, four host languages

Every example here embeds the same AHC-compiled library —
`tests/export/MathLib.hs` — from a different language, through
bindings that `ahc bindgen` generates:

    scripts/ahc-build.sh --lib tests/export/MathLib.hs mathlib.a
    ahc bindgen cpp  tests/export/MathLib.hs mathlib.a   # ahc_exports.hpp
    ahc bindgen rust tests/export/MathLib.hs mathlib.a   # ahc_exports.rs
    ahc bindgen go   tests/export/MathLib.hs mathlib.a   # ahc.go
    ahc bindgen ghc  tests/export/MathLib.hs mathlib.a   # AhcLib.hs

The C ABI is the hub: `foreign export ccall` produces plain C entry
points (`ahc_exports.h`), and each generated file wraps them in the
host language's own idiom —

- **cpp/** — an RAII class (`ahc::Lib`); constructing it runs
  `ahc_lib_init`, `std::string` crosses the boundary by copy.
- **rust/** — a module of safe wrappers over a raw `extern "C"`
  block; `&str -> String`, no `unsafe` in the caller.
- **go/** — a cgo package that funnels every call onto one locked
  OS thread, so *any* goroutine may call the wrappers despite the
  single-threaded runtime.
- **ghc/** — GHC `foreign import`s of the AHC entry points: two
  Haskell runtimes (GHC's RTS and AHC's graph reducer) in one
  process, calling each other through C.

`scripts/run_bindgen.sh` builds and runs whichever examples have
their toolchain installed (clang++ always; rustc/go/ghc when
present) and diffs each against its `expected.out`.

The embedding contract, in every language: initialize once, then
call from that same thread (the Go wrapper enforces this for you).
