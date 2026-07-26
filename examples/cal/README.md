# ahccal - the value-constraint example

A civil-calendar utility, and the worked tour of the Ada extension's
two halves working together: **refinement types** constraining values
(`docs/refinement-types-design-note.md`) and **Pre/Post contracts**
constraining functions (`docs/contracts-design-note.md`).

    ahccal 2026-07-25              weekday, ordinal day, leap flag, week
    ahccal 2026-07-25 +120         date arithmetic (+/- days)
    ahccal --cal 2026 7            month grid
    ahccal --between D1 D2         days between two dates
    ahccal --leapday 2028          February 29th of a leap year
    ahccal --zone 5.75 D HH:MM     UTC offset conversion (+ --dst)
    ahccal --syntax D              parse without demanding the date
    ahccal                         one command per line from stdin

## The point

The program contains **no hand-written validation**. Every bound,
every well-formedness test, every relationship between arguments is
declared - as a refinement on a type or as a contract on a function -
and the compiler inserts the checks:

    $ ./ahccal 2500-01-01
    date     refinement violation: 2500 not in 1900 .. 2400
    $ ./ahccal 2026-02-31
    date     ahc: precondition of 'mkDate' violated

Neither failure is written anywhere in `Main.hs`. (The partial line
before each message is not a bug - it is the demand-time semantics
made visible: `putStr` had already emitted the label when the value
behind it was finally forced.)

The division of labour is the thing to watch:

    type Day = Int in 1 .. 31              -- bounds ONE value
    {-# PRE mkDate \y m d -> d <= daysInMonth y m #-}
                                           -- relates THREE values

No per-value constraint can rule out February 31st, because the day's
legality depends on the month and the year. That is exactly the line
between Ada's subtype constraints and Ada's subprogram contracts, and
it is why AHC has both.

## What it exercises

| Feature | Where |
|---|---|
| Int ranges | `Year`, `Month`, `Day`, `DayOfYear` |
| `satisfying` predicate | `LeapYear`; `leapDay` cannot be called on 2027 |
| Modular types | `Weekday = Int mod 7`, `Minutes = Int mod 1440` |
| Double range | `Offset = Double in -12.0 .. 14.0` (+05:45 is real) |
| Refined constructor fields | `data Date = Date Year Month Day` |
| PRE relating arguments | `mkDate`, `fromOrdinal`, `addDays` |
| POST characterizing the result | `dateOf`/`dayNumber`, `addDays`, `daysBetween` |
| Contract calling user helpers | `daysInMonth` / `daysInYear` inside pragmas |
| Polymorphic contract | `clampTo :: Ord a => ...`, used at Int and at Double |
| Compile-time discharge | `gridRows`' capacity claim, folded away |
| Demand-time laziness | `--syntax`, which parses but never forces |

The date/integer isomorphism is fully specified: `dayNumber`'s and
`dateOf`'s postconditions say each inverts the other, `addDays` is
specified in terms of `dayNumber`, and `daysBetween` is specified by
adding its own answer back. Every call in the test suite checks all
of it, at demand time.

Two smaller points the code makes in passing: `weekdayOf dt` is an
`Int mod 7` that is added to and subtracted from plain `Int`s with no
unwrapping (refinements are erased for typechecking - the ergonomic
difference from a newtype and a smart constructor), and the
`weekdayName` / `monthName` lookups need no bounds check because the
argument's own type is the bound.

## Release mode

    AHC_UNCHECKED=1 scripts/ahc-build.sh examples/cal/Main.hs ahccal-u

Ada's assertion policy: every range check, predicate check and
contract claim is compiled out, and answers on valid input are
byte-identical (the harness asserts this). Modular **normalization
survives**, because wraparound is arithmetic rather than a claim -
without it `--zone -3.5 2026-07-25 01:00` would print `-2:-30`
instead of `21:30`. Invalid input, of course, is no longer caught:
the unchecked binary happily reports that 2026-02-31 is a Tuesday.

## Compile-time behavior

`gridRows`' precondition mentions no argument, so `AHC.Discharge`
folds it to `True` and the claim never reaches the generated C. Every
other contract here consumes an argument, gets stuck on it, and keeps
its runtime check - the correct conservative answer, and the reason
discharge can only ever be incomplete, never wrong.

One observed limit worth recording: a contract on a function whose
signature carries refinements is not discharged even when its claim
is argument-free (`calendarGrid :: Year -> Month -> ...` kept a claim
that the identical one on `gridRows :: [String] -> ...` discharged),
which is why the capacity claim lives on the helper. Incompleteness,
not unsoundness.

## GHC

Unlike `examples/lisp`, `examples/json` and `examples/hm`, this
program is **AHC-only by construction**, and it is the only example
that is. The contract pragmas are portable - GHC ignores them with a
warning - but `Int in 1 .. 31`, `Int mod 7` and
`Int satisfying isLeapYear` are the refinement surface, an AHC
extension GHC cannot parse. So the goldens in `tests/` are AHC's own
output rather than the GHC oracle's, and `scripts/run_examples.sh
--oracle` skips this program. The reason is in the feature, not in
the program: refinement types are the one part of AHC that has no
GHC translation, which is also the whole reason they exist.

## Tests

    scripts/run_examples.sh

`tests/*.in` are stdin scripts (`--` comments, one command per line);
`tests/*.golden` are the expected transcripts. The harness also
asserts the four constraint violations (bad year, February 31st, a
non-leap `--leapday`, an out-of-range UTC offset) fail with the right
message and a nonzero exit, and that the `--unchecked` build agrees
on every valid input.
