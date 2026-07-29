-- Engine: a small analysis library written in Haskell and embedded
-- by five host languages (C, C++, Rust, Go, GHC).
--
-- Each export is something you would actually want Haskell for -
-- an infinite lazy sieve, exact bignum arithmetic, a recursive
-- descent parser whose failures cross the boundary as the host's
-- own error type, and a word-frequency pass.
--
-- The library deliberately performs NO I/O of its own: `analyze`
-- reports through `host_log`, a C-ABI function each host implements
-- in its own language. So every byte of output is written by the
-- host (one buffer, one writer, deterministic order) and the demo
-- is a genuine round trip: host -> AHC -> host.
{-# LANGUAGE ForeignFunctionInterface #-}
module Engine where

import Data.Char (isAlpha, isDigit, isSpace, ord, toLower)
import Data.List (group, intercalate, sort, sortBy)

--  OUTBOUND: provided by whatever language embeds this library.
foreign import ccall "host_log" hostLog :: String -> IO ()

------------------------------------------------------------------
--  1. Laziness: an infinite sieve, cut to size at the boundary.
------------------------------------------------------------------

foreign export ccall primes :: CInt -> String

primes :: CInt -> String
primes n = intercalate "," (map show (take (fromIntegral n) sieve))

sieve :: [Int]
sieve = go [2 ..]
  where
    go [] = []
    go (p : xs) = p : go [x | x <- xs, mod x p /= 0]

------------------------------------------------------------------
--  2. Bignums: AHC's Int promotes instead of wrapping, so 100!
--     is exact. The host just receives the digits.
------------------------------------------------------------------

foreign export ccall factorial :: CInt -> String

factorial :: CInt -> String
factorial n = show (fac (fromIntegral n))

fac :: Integer -> Integer
fac k = if k <= 1 then 1 else k * fac (k - 1)

------------------------------------------------------------------
--  3. A parser. Bad input raises, and the boundary turns that into
--     a C++ exception / Rust Err / Go error / GHC IOError.
------------------------------------------------------------------

foreign export ccall evalExpr :: String -> Int

evalExpr :: String -> Int
evalExpr s =
  let (v, r) = pExpr (filter (not . isSpace) s)
  in if null r then v else error ("unexpected '" ++ take 8 r ++ "'")

pExpr :: String -> (Int, String)
pExpr s0 = goE (pTerm s0)
  where
    goE (v, '+' : r) = let (w, r2) = pTerm r in goE (v + w, r2)
    goE (v, '-' : r) = let (w, r2) = pTerm r in goE (v - w, r2)
    goE acc = acc

pTerm :: String -> (Int, String)
pTerm s0 = goT (pFactor s0)
  where
    goT (v, '*' : r) = let (w, r2) = pFactor r in goT (v * w, r2)
    goT (v, '/' : r) =
      let (w, r2) = pFactor r
      in if w == 0 then error "division by zero" else goT (div v w, r2)
    goT acc = acc

pFactor :: String -> (Int, String)
pFactor ('(' : r) =
  let (v, r2) = pExpr r
  in case r2 of
       ')' : r3 -> (v, r3)
       _ -> error "missing ')'"
pFactor ('-' : r) = let (v, r2) = pFactor r in (negate v, r2)
pFactor s =
  let (ds, r) = span isDigit s
  in if null ds
       then error ("expected a number at '" ++ take 8 s ++ "'")
       else (digits ds, r)

digits :: String -> Int
digits ds = foldl (\a c -> a * 10 + (ord c - ord '0')) 0 ds

------------------------------------------------------------------
--  4. Strings both ways: the five commonest words, ranked.
------------------------------------------------------------------

foreign export ccall wordFreq :: String -> String

wordFreq :: String -> String
wordFreq txt = intercalate ", " (map fmt (take 5 ranked))
  where
    norm c = if isAlpha c then toLower c else ' '
    ws = words (map norm txt)
    counted = map (\g -> (length g, head g)) (group (sort ws))
    ranked = sortBy cmp counted
    cmp (a, x) (b, y) = if a == b then compare x y else compare b a
    fmt (n, w) = w ++ ":" ++ show n

------------------------------------------------------------------
--  5. The round trip: AHC calls back OUT into the host language.
------------------------------------------------------------------

foreign export ccall analyze :: String -> IO CInt

analyze :: String -> IO CInt
analyze txt = do
  hostLog ("engine: " ++ show (length (words txt)) ++ " words in "
           ++ show (length (lines txt)) ++ " lines")
  hostLog ("engine: ranked -> " ++ wordFreq txt)
  return (fromIntegral (length (words txt)))
