# fastfibinwest - Fibonacci by fast doubling

    fastfib 100            print fib 100
    fastfib 0 1 2 90 300   one result per line
    fastfib                read indices from stdin, one per line

Blank lines and `--` comments in stdin scripts are skipped; each word
is answered independently, so a bad word reports an error and the
batch continues.

## What it exercises

AHC's arbitrary-precision `Integer` under real load. Fast doubling
turns fib into about log2 n big multiplications:

    fib (2k)   = fib k * (2 * fib (k+1) - fib k)
    fib (2k+1) = fib (k+1)^2 + fib k^2

so `fib 100000` (20899 digits) returns in ~0.03s and `fib 1000000`
(208988 digits) in ~1.1s, entirely inside the hand-rolled
sign-and-magnitude bignum in `runtime/ahc_rts.c`. The goldens cross
the machine-word boundary deliberately: `fib 92` is the last value
that fits a 64-bit Int and `fib 93` is the first that does not, so
AHC's limb arithmetic is compared against GMP right where the
representation changes.

The `{-# PRE fib \n -> n >= 0 #-}` contract states the obligation the
fold depends on. It cannot fire, because `main` rejects negative
input before calling `fib` - validate at the boundary, assert
inside. GHC ignores the pragma, so the program stays portable and the
goldens are GHC's output.

## What had to change

The original was three lines from working, and only one of the three
was a compiler gap:

1. `Main = do` (capital M) bound a nonexistent data constructor and
   left `main`'s signature without a binding. **Both** compilers
   rejected it.
2. `Data.Bits.bitSize` does not exist in AHC's `Data.Bits`. GHC 9.4
   still has it, deprecated, pointing at `finiteBitSize`.

`bitSize` was replaced by a `bitWidth` computed from `n` itself
rather than added to the standard library, because AHC has a
stronger reason than deprecation to avoid it: an AHC `Int` **promotes
to bignum on overflow** rather than wrapping, so it has no fixed
width to report honestly. Deriving the width from the value is also
shorter, and it removes the leading zeros the original had to strip
with `dropWhile not`.

Everything else in the original already worked: the
monomorphism-restricted `foldl_ = foldl'` in a `where`, the `let`
inside a list-comprehension generator, the descending stepped
enumeration, and the bignum arithmetic itself.

## Tests

    scripts/run_examples.sh
    scripts/run_examples.sh --oracle    # regenerate goldens under GHC

`tests/*.in` are stdin scripts and `tests/*.golden` is GHC 9.4.8's
output for them; the harness also checks argument mode.
