# M139 Data.Int, Data.Word, Data.IORef - Implementation Plan

**Goal:** GHC-shaped fixed-width integers (wrapping `Int8..Int64`,
`Word8..Word64`, `Word`) with their Report/base instances, a `Bits`
class over them, and `Data.IORef`.

**Architecture:** the eight fixed-width tycons already exist (wired for
the FFI, sharing Int's exact/promoting runtime representation) with
wired Eq/Ord/Show/Num/Integral dictionaries borrowed from Int. The
wired Num/Integral go away; Prelude SOURCE instances (generated,
one block) define every arithmetic result as Int's result NARROWED to
the width by one runtime primitive, which is what makes them wrap.
`IORef` is a wired opaque arity-1 tycon over a one-field constructor
node mutated in place behind the own collector's write barrier; the
library is four primitives and ordinary Haskell.

## Global constraints
- Oracle GHC 9.4.8; conformance goldens are its stdout.
- `Word` is a synonym for `Word64` (GHC: a distinct type) - EXCLUSIONS.
- Both GC modes; the IORef write is a mutation of a possibly old node: `own_write_barrier` after the store, exactly like a thunk update.
- Prelude and lib/ are gate inputs: no suite runs while Phase B edits them.

## Phase A - runtime + builtins
- `primNarrow bits signed v`: low 64 bits of an Int or bignum (two's complement), masked to `bits`, sign- or zero-extended; a Word64 above 2^63 comes back as a positive bignum (`ahc_mk_ulong`).
- `primFixCast :: a -> b`: the identity (representation cast Int8 <-> Int).
- `IORef` tycon; `primNewIORef`, `primReadIORef`, `primWriteIORef` (barriered), `primSameIORef`.
- Remove the wired Num/Integral `Def_Instance` for the fixed-width types (Eq/Ord/Show stay: Int's, correct on narrowed values).
- **Gate:** build, golden (renumber-only), exec.

## Phase B - library
- Prelude: generated instances for the 8 types: Num (wrapping), Bounded, Real, Enum (GHC's error texts: `Enum.toEnum{Word8}: tag (300) is outside of bounds (0,255)`, `Enum.succ{Int8}: tried to take \`succ' of maxBound`), Integral (`quot`/`div` of minBound by -1 raise ArithException Overflow), Read (wraps like GHC: `read "300" :: Word8` = 44); `type Word = Word64`.
- `lib/Data/Int.hs`, `lib/Data/Word.hs`: facades over the wired names.
- `lib/Data/Ix.hs`: instances for the 8 types.
- `lib/Data/Bits.hs`: `class Eq a => Bits a` with instances at Int and the 8 types (popCount/complement/shifts on the unsigned view, narrowed).
- `lib/Data/IORef.hs`: newIORef, readIORef, writeIORef, modifyIORef, modifyIORef', atomicModifyIORef, atomicModifyIORef', atomicWriteIORef, `Eq (IORef a)`.
- Conformance (oracled): lib_data_int_word.hs, lib_data_bits.hs, lib_data_ioref.hs; exec: ioref under Scoped tasks.
- **Gate:** conformance, exec both GC modes, golden, differential, examples, repl, unit.

## Phase C - write-up, review, release v1.12
- EXCLUSIONS (Data.Bits row rewritten; Data.Int/Word/IORef row), MANUAL ch. 18, README, CHANGES; adversarial review; `release: v1.12`.
