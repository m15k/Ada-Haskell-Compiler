-- ahccal - a civil-calendar utility, and the worked tour of AHC's
-- value constraints: Ada-style refinement types constraining the
-- VALUES, Ada-style Pre/Post contracts constraining the FUNCTIONS.
--
--   ahccal 2026-07-25              weekday, ordinal day, leap flag
--   ahccal 2026-07-25 +120         date arithmetic (+/- days)
--   ahccal --cal 2026 7            month grid
--   ahccal --between D1 D2         days between two dates
--   ahccal --leapday 2028          February 29th of a leap year
--   ahccal --zone 5.75 D HH:MM     UTC offset conversion (+ --dst)
--   ahccal --syntax D              parse without demanding the date
--   ahccal                         one command per line from stdin
--
-- The point of the program: it contains NO hand-written validation.
-- Every range check, every well-formedness test, every relationship
-- between arguments is stated declaratively - as a refinement on a
-- type or as a contract on a function - and the compiler inserts
-- the checks. `2500-01-01` dies with a refinement violation and
-- `2026-02-31` dies with a precondition violation, and neither
-- failure is written anywhere in this file.
--
-- The division of labour is the thing to watch:
--
--   type Day = Int in 1 .. 31          -- bounds ONE value
--   {-# PRE mkDate \y m d -> d <= daysInMonth y m #-}
--                                      -- relates THREE values
--
-- No per-value constraint can rule out February 31st, because the
-- day's legality depends on the month and the year. That is exactly
-- the line between Ada's subtype constraints and Ada's subprogram
-- contracts, and it is why AHC has both.
--
-- GHC note: unlike examples/lisp, examples/json and examples/hm,
-- this program is AHC-only by construction. The contract pragmas are
-- portable (GHC ignores them with a warning), but `Int in 1 .. 31`,
-- `Int mod 7` and `Int satisfying isLeapYear` are the refinement
-- surface - an AHC extension GHC cannot parse. So the goldens in
-- tests/ are AHC's own output, not the GHC oracle's. That is the one
-- house rule this example cannot satisfy, and the reason is in the
-- feature, not in the program.
--
-- Build and run:
--   scripts/ahc-build.sh examples/cal/Main.hs examples/cal/ahccal
--   ./examples/cal/ahccal 2026-07-25
--   AHC_UNCHECKED=1 scripts/ahc-build.sh ...   -- Ada's release mode

import Data.Char (isDigit, ord)
import Data.List (intercalate)
import System.Environment (getArgs)

------------------------------------------------------------------
--  The constrained types
------------------------------------------------------------------

-- Ranges. A value crossing one of these boundaries - an argument, a
-- result, a constructor field - is checked when it is demanded.
type Year      = Int in 1900 .. 2400
type Month     = Int in 1 .. 12
type Day       = Int in 1 .. 31
type DayOfYear = Int in 1 .. 366

-- Modular types. Not contracts but COERCIONS: a value crossing the
-- boundary is normalized into [0, N) with mathematical mod (never
-- negative), so weekday and clock arithmetic wrap the way Ada's
-- modular types wrap - and, being arithmetic rather than a claim,
-- the wrapping survives --unchecked.
type Weekday = Int mod 7      -- 0 = Sunday
type Minutes = Int mod 1440   -- minutes past local midnight

-- A Double range. Real UTC offsets are not whole hours: Nepal is
-- +5:45, Chatham Island +12:45.
type Offset = Double in -12.0 .. 14.0

-- A predicate refinement. The predicate is ordinary typechecked
-- Haskell compiled to a hidden top-level function; `leapDay` below
-- cannot be called on a year that has no February 29th.
isLeapYear :: Int -> Bool
isLeapYear y = (y `mod` 4 == 0 && y `mod` 100 /= 0) || y `mod` 400 == 0

type LeapYear = Int satisfying isLeapYear

-- Refined types are legal in constructor fields, so every Date ever
-- built is checked at construction - including through partial
-- application (`map (Date 2026 7) days`). Field READS trust the
-- invariant the constructor established, which is why the accessors
-- below return plain Int.
data Date = Date Year Month Day deriving (Eq, Ord)

yearOf :: Date -> Int
yearOf (Date y _ _) = y

monthOf :: Date -> Int
monthOf (Date _ m _) = m

dayOf :: Date -> Int
dayOf (Date _ _ d) = d

------------------------------------------------------------------
--  Calendar arithmetic (the contracts live here)
------------------------------------------------------------------

{-# POST daysInMonth \y m r -> r >= 28 && r <= 31 #-}
daysInMonth :: Year -> Month -> Int
daysInMonth y m
  | m == 2 = if isLeapYear y then 29 else 28
  | m == 4 || m == 6 || m == 9 || m == 11 = 30
  | otherwise = 31

{-# POST daysInYear \y r -> r == 365 || r == 366 #-}
daysInYear :: Year -> Int
daysInYear y = if isLeapYear y then 366 else 365

--  The showcase. `Day` already bounds d to 1 .. 31; only a contract
--  can say that the bound actually depends on the other two
--  arguments. The postcondition then pins that mkDate stores what it
--  was given - a small spec, but the one every later contract leans
--  on when it names yearOf/monthOf/dayOf.
{-# PRE  mkDate \y m d -> d <= daysInMonth y m #-}
{-# POST mkDate \y m d r -> yearOf r == y && monthOf r == m && dayOf r == d #-}
mkDate :: Year -> Month -> Day -> Date
mkDate y m d = Date y m d

{-# POST toOrdinal \dt r -> r <= daysInYear (yearOf dt) #-}
toOrdinal :: Date -> DayOfYear
toOrdinal dt =
  dayOf dt + sum (map (daysInMonth (yearOf dt)) [1 .. monthOf dt - 1])

--  Division of labour, stated out loud: `n >= 1` is the refinement's
--  job (DayOfYear starts at 1), `n <= daysInYear y` is the
--  contract's, because it depends on the other argument. The
--  postcondition is a full characterization - it says fromOrdinal
--  inverts toOrdinal, so an implementation bug that survives it is a
--  bug in the specification too.
{-# PRE  fromOrdinal \y n -> n <= daysInYear y #-}
{-# POST fromOrdinal \y n r -> toOrdinal r == n && yearOf r == y #-}
fromOrdinal :: Year -> DayOfYear -> Date
fromOrdinal y n = walk 1 n
  where
    -- Local helpers cannot carry contracts (top-level functions with
    -- signatures only, v1 scope) - which is a fair reason to keep the
    -- contracted surface small and the helpers under it.
    walk m k =
      let len = daysInMonth y m
      in if k <= len then mkDate y m k else walk (m + 1) (k - len)

--  Days since 1900-01-01, and its inverse. Between them these two
--  postconditions characterize the whole date/integer isomorphism,
--  and every later function is specified in terms of them.
{-# POST dayNumber \dt r -> r >= 0 #-}
dayNumber :: Date -> Int
dayNumber dt = yearsBefore 1900 + toOrdinal dt - 1
  where
    yearsBefore y =
      if y >= yearOf dt then 0 else daysInYear y + yearsBefore (y + 1)

{-# PRE  dateOf \n -> n >= 0 #-}
{-# POST dateOf \n r -> dayNumber r == n #-}
dateOf :: Int -> Date
dateOf n = walk 1900 n
  where
    walk y k =
      let len = daysInYear y
      in if k < len then fromOrdinal y (k + 1) else walk (y + 1) (k - len)

{-# PRE  addDays \dt n -> dayNumber dt + n >= 0 #-}
{-# POST addDays \dt n r -> dayNumber r == dayNumber dt + n #-}
addDays :: Date -> Int -> Date
addDays dt n = dateOf (dayNumber dt + n)

--  A postcondition proved by a DIFFERENT route than the body takes:
--  the body subtracts day numbers, the contract adds the answer back
--  and demands the second date.
{-# POST daysBetween \a b r -> addDays a r == b #-}
daysBetween :: Date -> Date -> Int
daysBetween a b = dayNumber b - dayNumber a

--  1900-01-01 was a Monday. The result crosses a `Int mod 7`
--  boundary, so it normalizes - no `mod` in the body, and negative
--  day numbers could not produce a negative weekday even if they
--  arose.
weekdayOf :: Date -> Weekday
weekdayOf dt = dayNumber dt + 1

--  The last representable day, and the Sunday-to-Saturday week
--  around a date. Note what the arithmetic looks like: `weekdayOf dt`
--  is a `Int mod 7` and it is added to and subtracted from plain Ints
--  with no unwrapping, because a refined type IS its base type to the
--  typechecker. That erasure is the whole ergonomic difference from a
--  newtype and a smart constructor.
lastDayNumber :: Int
lastDayNumber = dayNumber (mkDate 2400 12 31)

{-# POST weekOf \dt r -> dayNumber (snd r) - dayNumber (fst r) <= 6 #-}
weekOf :: Date -> (Date, Date)
weekOf dt =
  let n = dayNumber dt
      w = weekdayOf dt
  in ( dateOf (clampTo 0 lastDayNumber (n - w))
     , dateOf (clampTo 0 lastDayNumber (n + 6 - w)) )

--  Both of these lookups are total, and neither needs a bounds
--  check: the argument's own type guarantees the index.
weekdayName :: Weekday -> String
weekdayName w =
  nth w [ "Sunday", "Monday", "Tuesday", "Wednesday"
        , "Thursday", "Friday", "Saturday" ]

monthName :: Month -> String
monthName m =
  nth (m - 1) [ "January", "February", "March", "April", "May", "June"
              , "July", "August", "September", "October", "November"
              , "December" ]

--  The predicate refinement in use: a non-leap year cannot reach the
--  body, so mkDate's precondition here is trivially satisfiable.
leapDay :: LeapYear -> Date
leapDay y = mkDate y 2 29

--  A polymorphic contract. The lambdas are typechecked against a
--  signature derived from this one - `Ord a` and all - so the same
--  contract holds at every instantiation; it is used below at Int
--  (clamping a requested year) and at Double (clamping a summertime
--  offset). Clamping is how a value is brought INTO a refined type's
--  range without a hand-written check.
{-# PRE  clampTo \lo hi x -> lo <= hi #-}
{-# POST clampTo \lo hi x r -> r >= lo && r <= hi #-}
clampTo :: Ord a => a -> a -> a -> a
clampTo lo hi x = if x < lo then lo else if x > hi then hi else x

------------------------------------------------------------------
--  Time zones: a Double range in, a modular clock out
------------------------------------------------------------------

{-# POST zoneMinutes \o r -> r >= -720 && r <= 840 #-}
zoneMinutes :: Offset -> Int
zoneMinutes o = fromInteger (round (o * 60))

--  The sum can be negative or past midnight; the `Minutes` boundary
--  normalizes it into a real time of day.
localMinutes :: Minutes -> Offset -> Minutes
localMinutes t o = t + zoneMinutes o

--  ... and the day it lands on, which modular arithmetic deliberately
--  throws away, comes from floored division on plain Int.
dayShift :: Int -> Offset -> Int
dayShift t o = (t + zoneMinutes o) `div` 1440

------------------------------------------------------------------
--  Rendering
------------------------------------------------------------------

--  A postcondition that FORCES its result: contracts observe, and
--  measuring the length of the string is the one semantic footprint.
{-# POST showDate \dt r -> length r == 10 #-}
showDate :: Date -> String
showDate dt =
  zeroPad 4 (yearOf dt) ++ "-" ++ zeroPad 2 (monthOf dt)
    ++ "-" ++ zeroPad 2 (dayOf dt)

showClock :: Minutes -> String
showClock t = zeroPad 2 (t `div` 60) ++ ":" ++ zeroPad 2 (t `mod` 60)

showOffset :: Offset -> String
showOffset o =
  let m = zoneMinutes o
      s = if m < 0 then "-" else "+"
      a = abs m
  in s ++ zeroPad 2 (a `div` 60) ++ ":" ++ zeroPad 2 (a `mod` 60)

calendarGrid :: Year -> Month -> [String]
calendarGrid y m =
  let first = weekdayOf (mkDate y m 1)
      cells = replicate first "  "
                ++ map (padLeft 2 . show) [1 .. daysInMonth y m]
      title = centre 20 (monthName m ++ " " ++ show y)
  in title : "Su Mo Tu We Th Fr Sa" : gridRows cells

--  Six rows of seven cells hold any month with any starting weekday
--  (31 + 6 = 37, and 7 * 6 = 42). The claim mentions no argument, so
--  the discharge evaluator folds it to True at compile time and it
--  never reaches the generated code at all - Ada's "what the compiler
--  can prove, the runtime need not check". Every other contract in
--  this file consumes an argument, gets stuck on it, and keeps its
--  runtime check, which is the correct conservative answer.
{-# PRE gridRows \cells -> 7 * 6 >= 31 + 6 #-}
gridRows :: [String] -> [String]
gridRows cells = map row (chunksOf 7 cells)
  where
    row cs = trimRight (intercalate " " cs)

------------------------------------------------------------------
--  Commands
------------------------------------------------------------------

runCommand :: [String] -> [String]
runCommand args = case args of
  ["--help"] -> usage
  ["--syntax", s] -> syntaxOnly s
  ["--cal", y, m] -> monthGrid y m
  ["--leapday", y] -> leapDayOf y
  ["--between", a, b] -> spanOf a b
  ["--zone", o, d, t] -> zoneAt o d t False
  ["--zone", o, d, t, "--dst"] -> zoneAt o d t True
  [d] | not (isFlag d) -> info d
  [d, n] | not (isFlag d) -> shifted d n
  (a : _) -> ["error: unknown command '" ++ a ++ "' (try --help)"]
  [] -> usage

isFlag :: String -> Bool
isFlag s = take 2 s == "--"

info :: String -> [String]
info s = case parseDate s of
  Nothing -> [badDate s]
  Just dt ->
    [ "date     " ++ showDate dt
    , "weekday  " ++ weekdayName (weekdayOf dt)
    , "ordinal  " ++ show (toOrdinal dt) ++ " of "
                  ++ show (daysInYear (yearOf dt))
    , "leap     " ++ (if isLeapYear (yearOf dt) then "yes" else "no")
    , "week     " ++ showDate (fst (weekOf dt)) ++ " .. "
                  ++ showDate (snd (weekOf dt))
    ]

shifted :: String -> String -> [String]
shifted s n = case parseDate s of
  Nothing -> [badDate s]
  Just dt -> case readInt n of
    Nothing -> ["error: bad day count '" ++ n ++ "'"]
    Just k ->
      let r = addDays dt k
          op = if k < 0 then " - " else " + "
      in [ showDate dt ++ op ++ show (abs k) ++ " days = " ++ showDate r
             ++ " (" ++ weekdayName (weekdayOf r) ++ ")" ]

spanOf :: String -> String -> [String]
spanOf a b = case parseDate a of
  Nothing -> [badDate a]
  Just da -> case parseDate b of
    Nothing -> [badDate b]
    Just db ->
      let n = daysBetween da db
      in [ showDate da ++ " .. " ++ showDate db ++ " = " ++ plural n "day"
             ++ " (" ++ plural (n `div` 7) "week" ++ " + "
             ++ plural (n `mod` 7) "day" ++ ")" ]

plural :: Int -> String -> String
plural n w = show n ++ " " ++ w ++ (if n == 1 then "" else "s")

--  clampTo at Int: a year outside the supported window is brought
--  into range rather than crashing the grid.
monthGrid :: String -> String -> [String]
monthGrid ys ms = case readInt ys of
  Nothing -> ["error: bad year '" ++ ys ++ "'"]
  Just y -> case readInt ms of
    Nothing -> ["error: bad month '" ++ ms ++ "'"]
    Just m -> calendarGrid (clampTo 1900 2400 y) m

leapDayOf :: String -> [String]
leapDayOf ys = case readInt ys of
  Nothing -> ["error: bad year '" ++ ys ++ "'"]
  Just y -> let d = leapDay y in [showDate d ++ " (" ++ weekdayName (weekdayOf d) ++ ")"]

zoneAt :: String -> String -> String -> Bool -> [String]
zoneAt os ds ts dst = case readDouble os of
  Nothing -> ["error: bad offset '" ++ os ++ "'"]
  Just o0 -> case parseDate ds of
    Nothing -> [badDate ds]
    Just dt -> case readClock ts of
      Nothing -> ["error: bad time '" ++ ts ++ "'"]
      Just t ->
        let o = if dst then clampTo (-12.0) 14.0 (o0 + 1.0) else o0
            local = addDays dt (dayShift t o)
        in [ showDate dt ++ " " ++ showClock t ++ " UTC = "
               ++ showDate local ++ " " ++ showClock (localMinutes t o)
               ++ " (" ++ showOffset o ++ ")" ]

--  Laziness, visible: parseDate builds the Date but demands nothing,
--  so neither the field refinements nor mkDate's precondition fire.
--  An unchecked value that is never used is never checked - the same
--  rule the whole extension obeys.
syntaxOnly :: String -> [String]
syntaxOnly s = case parseDate s of
  Nothing -> [badDate s]
  Just dt -> [const ("syntax ok: " ++ s ++ " (not demanded)") dt]

badDate :: String -> String
badDate s = "error: bad date '" ++ s ++ "' (want YYYY-MM-DD)"

usage :: [String]
usage =
  [ "ahccal - a calendar built on value constraints"
  , "  ahccal DATE                weekday, ordinal day, leap flag"
  , "  ahccal DATE [+-]N          add or subtract days"
  , "  ahccal --cal YEAR MONTH    month grid"
  , "  ahccal --between D1 D2     days between two dates"
  , "  ahccal --leapday YEAR      February 29th"
  , "  ahccal --zone OFF D HH:MM  UTC offset conversion (+ --dst)"
  , "  ahccal --syntax DATE       parse without demanding the date"
  , "  ahccal                     read commands from stdin"
  ]

------------------------------------------------------------------
--  Parsing (syntax only - the constraints do the validating)
------------------------------------------------------------------

parseDate :: String -> Maybe Date
parseDate s = case splitOn '-' s of
  [y, m, d] ->
    if length y == 4 && digitsOnly y && digitsOnly m && digitsOnly d
      then Just (mkDate (digitsVal y) (digitsVal m) (digitsVal d))
      else Nothing
  _ -> Nothing

readInt :: String -> Maybe Int
readInt s = case s of
  ('-' : t) -> if digitsOnly t then Just (negate (digitsVal t)) else Nothing
  ('+' : t) -> if digitsOnly t then Just (digitsVal t) else Nothing
  _ -> if digitsOnly s then Just (digitsVal s) else Nothing

readDouble :: String -> Maybe Double
readDouble s = case s of
  ('-' : t) -> case readPositive t of
    Nothing -> Nothing
    Just v -> Just (negate v)
  ('+' : t) -> readPositive t
  _ -> readPositive s

readPositive :: String -> Maybe Double
readPositive s = case break (== '.') s of
  (ip, []) -> if digitsOnly ip then Just (fromIntegral (digitsVal ip)) else Nothing
  (ip, _ : fp) ->
    if digitsOnly ip && digitsOnly fp
      then Just (fromIntegral (digitsVal ip)
                   + fromIntegral (digitsVal fp) / 10 ^ length fp)
      else Nothing

readClock :: String -> Maybe Int
readClock s = case break (== ':') s of
  (h, _ : m) ->
    if digitsOnly h && digitsOnly m && length m == 2
      then Just (digitsVal h * 60 + digitsVal m)
      else Nothing
  _ -> Nothing

digitsOnly :: String -> Bool
digitsOnly s = not (null s) && all isDigit s

digitsVal :: String -> Int
digitsVal s = foldl (\acc c -> acc * 10 + (ord c - ord '0')) 0 s

------------------------------------------------------------------
--  Small helpers
------------------------------------------------------------------

nth :: Int -> [a] -> a
nth _ [] = error "nth: index out of range"
nth k (x : xs) = if k <= 0 then x else nth (k - 1) xs

splitOn :: Char -> String -> [String]
splitOn c s = case break (== c) s of
  (chunk, []) -> [chunk]
  (chunk, _ : rest) -> chunk : splitOn c rest

chunksOf :: Int -> [a] -> [[a]]
chunksOf _ [] = []
chunksOf n xs = case splitAt n xs of
  (a, b) -> a : chunksOf n b

zeroPad :: Int -> Int -> String
zeroPad w n = let s = show n in replicate (w - length s) '0' ++ s

padLeft :: Int -> String -> String
padLeft w s = replicate (w - length s) ' ' ++ s

centre :: Int -> String -> String
centre w s = replicate ((w - length s) `div` 2) ' ' ++ s

trimRight :: String -> String
trimRight = reverse . dropWhile (== ' ') . reverse

------------------------------------------------------------------
--  Driver
------------------------------------------------------------------

runLine :: String -> [String]
runLine ln =
  let ws = words ln
  in if null ws || isComment ln then [] else ("> " ++ unwords ws) : runCommand ws ++ [""]

isComment :: String -> Bool
isComment ln = case dropWhile (== ' ') ln of
  ('-' : '-' : rest) -> null rest || take 1 rest == " "
  _ -> False

main :: IO ()
main = do
  args <- getArgs
  if null args
    then getContents >>= \s -> putStr (unlines (concatMap runLine (lines s)))
    else putStr (unlines (runCommand args))
