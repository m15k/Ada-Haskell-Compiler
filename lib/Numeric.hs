module Numeric
  ( showHex, showOct, showIntAtBase
  , readHex, readOct, readDec
  , showEFloat, showFFloat, showGFloat, showFFloatAlt, showGFloatAlt
  , floatToDigits
  ) where

import Data.Char (intToDigit, digitToInt, isDigit, isHexDigit,
                  isOctDigit)
import Data.Ratio (numerator, denominator)

showIntAtBase :: Int -> (Int -> Char) -> Int -> String -> String
showIntAtBase base toDig n s
  | n < 0     = error "Numeric.showIntAtBase: negative"
  | n < base  = toDig n : s
  | otherwise =
      showIntAtBase base toDig (div n base)
        (toDig (mod n base) : s)

showHex :: Int -> String -> String
showHex n s = showIntAtBase 16 intToDigit n s

showOct :: Int -> String -> String
showOct n s = showIntAtBase 8 intToDigit n s

readIntAtBase :: Int -> (Char -> Bool) -> String -> [(Int, String)]
readIntAtBase base ok s =
  case span ok s of
    ([], _)      -> []
    (digits, r)  ->
      [(foldl (\a c -> a * base + digitToInt c) 0 digits, r)]

readDec :: String -> [(Int, String)]
readDec s = readIntAtBase 10 isDigit s

readHex :: String -> [(Int, String)]
readHex s = readIntAtBase 16 isHexDigit s

readOct :: String -> [(Int, String)]
readOct s = readIntAtBase 8 isOctDigit s

------------------------------------------------------------------
-- Floating-point formatting (M142), transcribed from GHC 9.4's
-- GHC.Float (formatRealFloatAlt, roundTo - round half to even).
-- The one adaptation: floatToDigits takes GHC's shortest digits from
-- `show`, which prints them already (the conformance suite pins it),
-- so the constraint is (RealFloat a, Show a) - a polymorphic caller
-- needs Show too (EXCLUSIONS).
------------------------------------------------------------------

-- | floatToDigits base x, for x >= 0: digits ds and exponent e with
-- x = 0.ds * base^e, shortest, as GHC's. Base 10 reads the digits off
-- `show`; every other base runs GHC's Burger-Dybvig generator.
floatToDigits :: (RealFloat a, Show a) => Integer -> a -> ([Int], Int)
floatToDigits base x
  | x == 0    = ([0], 0)
  | base /= 10 = floatToDigitsGen base x
  | otherwise =
      let s = show x
          (mant, ex) = break (== 'e') s
          e10 = case ex of
                  ('e' : '-' : n) -> negate (read n)
                  ('e' : n)       -> read n
                  _               -> 0 :: Int
          (ip, fp) = break (== '.') mant
          digits = map digitToInt (ip ++ drop 1 fp)
          lead = length (takeWhile (== 0) digits)
          ds = reverse (dropWhile (== 0) (reverse (drop lead digits)))
          e = length ip + e10 - lead
      in (if null ds then [0] else ds, e)

-- GHC.Float's floatToDigits, transcribed (Burger and Dybvig's free-
-- format algorithm), for the bases other than 10. AHC's Prelude has no
-- decodeFloat (EXCLUSIONS), so the IEEE double is decoded from its
-- exact toRational - GHC's normalised 53-bit mantissa, subnormals
-- included. A Float is a double at run time here, so it decodes as
-- one (EXCLUSIONS).
floatToDigitsGen :: RealFloat a => Integer -> a -> ([Int], Int)
floatToDigitsGen base x =
  let (f0, e0) = decodeDouble x
      minExp0 = -1021 :: Int
      p = 53 :: Int
      b = 2 :: Integer
      minExp = minExp0 - p
      (f, e) = let n = minExp - e0 in
               if n > 0 then (f0 `quot` (b ^ n), e0 + n) else (f0, e0)
      (r, s, mUp, mDn) =
        if e >= 0 then
          let be = b ^ e in
          if f == b ^ (p - 1)
            then (f * be * b * 2, 2 * b, be * b, be)
            else (f * be * 2, 2, be, be)
        else
          if e > minExp && f == b ^ (p - 1)
            then (f * b * 2, b ^ (negate e + 1) * 2, b, 1)
            else (f * 2, b ^ negate e * 2, 1, 1)
      k0 :: Int
      k0 = fromInteger (ceiling ((log (fromInteger (f + 1) :: Double)
                     + fromIntegral e * log (fromInteger b))
                    / log (fromInteger base)))
      fixup n =
        if n >= 0
          then if r + mUp <= base ^ n * s then n else fixup (n + 1)
          else if base ^ negate n * (r + mUp) <= s then n else fixup (n + 1)
      k = fixup k0
      gen ds rn sN mUpN mDnN =
        let (dn, rn') = (rn * base) `quotRem` sN
            mUpN' = mUpN * base
            mDnN' = mDnN * base
        in case (rn' < mDnN', rn' + mUpN' > sN) of
             (True,  False) -> dn : ds
             (False, True)  -> dn + 1 : ds
             (True,  True)  -> if rn' * 2 < sN then dn : ds else dn + 1 : ds
             (False, False) -> gen (dn : ds) rn' sN mUpN' mDnN'
      rds = if k >= 0
              then gen [] r (s * base ^ k) mUp mDn
              else let bk = base ^ negate k in gen [] (r * bk) s (mUp * bk) (mDn * bk)
  in (map fromInteger (reverse rds), k)

decodeDouble :: RealFloat a => a -> (Integer, Int)
decodeDouble x =
  let q = toRational (abs x)
      n = numerator q
      d = denominator q
      e = ilog2 n - ilog2 d - 52
      m = if e >= 0 then n `div` (d * 2 ^ e) else (n * 2 ^ negate e) `div` d
  in (if x < 0 then negate m else m, e)
  where
    ilog2 :: Integer -> Int
    ilog2 v = go 0 v
      where go acc w = if w <= 1 then acc else go (acc + 1) (w `div` 2)

data FFFormat = FFExponent | FFFixed | FFGeneric

showEFloat :: (RealFloat a, Show a) => Maybe Int -> a -> String -> String
showEFloat d x = showString (formatRealFloatAlt FFExponent d False x)

showFFloat :: (RealFloat a, Show a) => Maybe Int -> a -> String -> String
showFFloat d x = showString (formatRealFloatAlt FFFixed d False x)

showGFloat :: (RealFloat a, Show a) => Maybe Int -> a -> String -> String
showGFloat d x = showString (formatRealFloatAlt FFGeneric d False x)

showFFloatAlt :: (RealFloat a, Show a) => Maybe Int -> a -> String -> String
showFFloatAlt d x = showString (formatRealFloatAlt FFFixed d True x)

showGFloatAlt :: (RealFloat a, Show a) => Maybe Int -> a -> String -> String
showGFloatAlt d x = showString (formatRealFloatAlt FFGeneric d True x)

formatRealFloatAlt :: (RealFloat a, Show a)
                   => FFFormat -> Maybe Int -> Bool -> a -> String
formatRealFloatAlt fmt decs alt x
  | isNaN x                   = "NaN"
  | isInfinite x              = if x < 0 then "-Infinity" else "Infinity"
  | x < 0 || isNegativeZero x = '-' : doFmt fmt (floatToDigits 10 (negate x))
  | otherwise                 = doFmt fmt (floatToDigits 10 x)
  where
    base = 10

    doFmt format (is, e) =
      let ds = map intToDigit is in
      case format of
        FFGeneric ->
          doFmt (if e < 0 || e > 7 then FFExponent else FFFixed) (is, e)
        FFExponent ->
          case decs of
            Nothing ->
              let show_e' = show (e - 1) in
              case ds of
                "0"       -> "0.0e0"
                [d]       -> d : ".0e" ++ show_e'
                (d : ds') -> d : '.' : ds' ++ "e" ++ show_e'
                []        -> error "formatRealFloat/doFmt/FFExponent: []"
            Just d | d <= 0 ->
              case is of
                [0] -> "0e0"
                _ ->
                  let (ei, is') = roundTo base 1 is
                      n = head (map intToDigit (if ei > 0 then init is' else is'))
                  in n : 'e' : show (e - 1 + ei)
            Just dec ->
              let dec' = max dec 1 in
              case is of
                [0] -> '0' : '.' : take dec' (repeat '0') ++ "e0"
                _ ->
                  let (ei, is') = roundTo base (dec' + 1) is
                      dds = map intToDigit (if ei > 0 then init is' else is')
                  in head dds : '.' : tail dds ++ 'e' : show (e - 1 + ei)
        FFFixed ->
          let mk0 ls = case ls of { "" -> "0"; _ -> ls } in
          case decs of
            Nothing
              | e <= 0    -> "0." ++ replicate (negate e) '0' ++ ds
              | otherwise ->
                  let f 0 s rs       = mk0 (reverse s) ++ '.' : mk0 rs
                      f n s ""       = f (n - 1) ('0' : s) ""
                      f n s (r : rs) = f (n - 1) (r : s) rs
                  in f e "" ds
            Just dec ->
              let dec' = max dec 0 in
              if e >= 0
                then
                  let (ei, is') = roundTo base (dec' + e) is
                      (ls, rs) = splitAt (e + ei) (map intToDigit is')
                  in mk0 ls ++ (if null rs && not alt then "" else '.' : rs)
                else
                  let (ei, is') = roundTo base dec' (replicate (negate e) 0 ++ is)
                      dds = map intToDigit (if ei > 0 then is' else 0 : is')
                  in head dds : (if null (tail dds) && not alt then "" else '.' : tail dds)

roundTo :: Int -> Int -> [Int] -> (Int, [Int])
roundTo base d is =
  case f d True is of
    x@(0, _) -> x
    (1, xs)  -> (1, 1 : xs)
    _        -> error "roundTo: bad Value"
  where
    b2 = base `quot` 2
    f n _ [] = (0, replicate n 0)
    f 0 e (x : xs)
      | x == b2 && e && all (== 0) xs = (0, [])
      | otherwise = (if x >= b2 then 1 else 0, [])
    f n _ (i : xs)
      | i' == base = (1, 0 : is')
      | otherwise  = (0, i' : is')
      where
        (c, is') = f (n - 1) (even i) xs
        i' = c + i
