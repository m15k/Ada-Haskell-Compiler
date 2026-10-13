# The spokes: one Haskell engine, five host languages

`engine/Engine.hs` is a small analysis library written in Haskell.
Five programs embed it — in C, C++, Rust, Go, and GHC — and each one
exercises **both directions at once**: the host calls the Haskell
exports, and the Haskell library calls back out into the host.

    ahc build --lib  examples/ffi/engine/Engine.hs engine.a
    ahc bindgen cpp  examples/ffi/engine/Engine.hs engine.a  # engine.a.build/ahc_exports.hpp
    ahc bindgen rust examples/ffi/engine/Engine.hs engine.a  # engine.a.build/ahc_exports.rs
    ahc bindgen go   examples/ffi/engine/Engine.hs engine.a  # engine.a.build/ahc.go
    ahc bindgen ghc  examples/ffi/engine/Engine.hs engine.a  # engine.a.build/AhcLib.hs

Every line names the same library on purpose: `OUT` in
`ahc bindgen LANG FILE.hs OUT` is the archive, not the binding.
Each language's wrapper lands beside `ahc_exports.h` in
`engine.a.build/`, so all five hosts link the one `engine.a`.
C needs no generator: `engine.a.build/ahc_exports.h` *is* the C
binding, and the other four are generated wrappers over it.

## Building each host

Run these from the repository root, after the `ahc build --lib` and
`ahc bindgen` lines above. `ahc build --lib` ends its output with a
`link with:` line: the flags every host must add to pull in the
collector the archive was built against. Set `LINK` to whatever it
printed, as an array so the flags split the same way in bash and
zsh (`LINK=()` when built without Boehm):

    LINK=(-L"$(brew --prefix bdw-gc)/lib" -lgc)   # from "link with:"

**C** — include the generated header, link the archive:

    clang -I engine.a.build -o c_main examples/ffi/c/main.c engine.a "${LINK[@]}"

**C++** — `ahc_exports.hpp` sits beside `ahc_exports.h`:

    clang++ -std=c++17 -I engine.a.build -o cpp_main \
      examples/ffi/cpp/main.cpp engine.a "${LINK[@]}"

**Rust** — `main.rs` says `mod ahc_exports;`, so the generated
module must sit beside it; the archive goes to the linker:

    mkdir -p rust_build
    cp examples/ffi/rust/main.rs engine.a.build/ahc_exports.rs rust_build/
    rustc --edition 2021 -O rust_build/main.rs \
      -C link-args="engine.a ${LINK[*]}" -o rust_main

**Go** — the binding is the `ahcgo/ahc` package; its cgo preamble
links `${SRCDIR}/engine.a`, so the archive and header travel with it:

    mkdir -p go_build/ahc
    cp examples/ffi/go/main.go examples/ffi/go/go.mod go_build/
    cp engine.a.build/ahc.go engine.a.build/ahc_exports.h engine.a go_build/ahc/
    (cd go_build && CGO_LDFLAGS="${LINK[*]}" go build -o ../go_main .)

**GHC** — compile `Main.hs` with the generated `AhcLib.hs`:

    ghc -O -outputdir ghc_build -o ghc_main \
      examples/ffi/ghc/Main.hs engine.a.build/AhcLib.hs engine.a "${LINK[@]}"

Each binary's output should match its directory's `expected.out`.

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
