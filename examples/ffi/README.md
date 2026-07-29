# The spokes: one Haskell engine, five host languages

`engine/Engine.hs` is a small analysis library written in Haskell.
Five programs embed it — in C, C++, Rust, Go, and GHC — and each one
exercises **both directions at once**: the host calls the Haskell
exports, and the Haskell library calls back out into the host.

    scripts/ahc-build.sh --lib examples/ffi/engine/Engine.hs engine.a
    ahc bindgen cpp  examples/ffi/engine/Engine.hs engine.a  # .hpp
    ahc bindgen rust examples/ffi/engine/Engine.hs engine.a  # .rs
    ahc bindgen go   examples/ffi/engine/Engine.hs engine.a  # ahc.go
    ahc bindgen ghc  examples/ffi/engine/Engine.hs engine.a  # AhcLib.hs

C needs no generator: `engine.a.build/ahc_exports.h` *is* the C
binding, and the other four are generated wrappers over it.

## What the engine exports, and why

Each export is something you would plausibly reach for Haskell to do:

| Export | Demonstrates |
|---|---|
| `primes :: CInt -> String` | an **infinite** lazy sieve, cut to size at the boundary |
| `factorial :: CInt -> String` | exact bignums — `30!` is 33 digits, no `int64` in sight |
| `evalExpr :: String -> Int` | a recursive-descent parser; bad input **raises** |
| `wordFreq :: String -> String` | strings in and out, ranked word counts |
| `analyze :: String -> IO CInt` | the round trip — calls back into the host |

## The round trip

`Engine.hs` opens with an *import*, not an export:

```haskell
foreign import ccall "host_log" hostLog :: String -> IO ()
```

Nothing in the library defines `host_log`; the archive simply
carries the undefined symbol, and **each host supplies it in its own
language** — a C function, an `extern "C"` C++ function, a Rust
`#[no_mangle] extern "C" fn`, a cgo `//export`, or a GHC
`foreign export ccall`. The linker ties the knot. When `analyze`
runs, the `[c]` / `[rust]` / `[ghc]` lines in the output are Haskell
calling *out* mid-computation.

The GHC example is the extreme case: two independent Haskell
runtimes — GHC's RTS and AHC's graph reducer — in one process,
each exporting to and importing from the other through C.

Because the library performs no I/O of its own, every byte of output
is written by the host: one writer, one buffer, deterministic
ordering across five very different runtimes.

## Errors

`evalExpr "2 +"` fails inside the library. It does not kill the
process — the boundary converts it into whatever that host calls a
failure, and the next call works normally:

| Host | Failure arrives as |
|---|---|
| C | `ahc_last_error()` after a 0/NULL return |
| C++ | `std::runtime_error` |
| Rust | `Err(String)` from a `Result` |
| Go | a non-nil `error` |
| GHC | `IOError` (`user error (...)`) |

`scripts/run_bindgen.sh` builds and runs whichever examples have
their toolchain installed and diffs each against its `expected.out`.
