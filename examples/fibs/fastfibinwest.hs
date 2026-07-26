-- fastfibinwest - Fibonacci by fast doubling, over AHC's
-- arbitrary-precision Integer.
--
--   fastfib 100            print fib 100
--   fastfib 0 1 2 90 300   one result per line
--   fastfib                read indices from stdin, one per line
--
-- The algorithm walks the bits of n from the top down, maintaining
-- the pair (fib (k+1), fib k) and doubling at each step:
--
--   fib (2k)   = fib k * (2 * fib (k+1) - fib k)
--   fib (2k+1) = fib (k+1)^2 + fib k^2
--
-- so it needs about log2 n big multiplications rather than n
-- additions - fib 100000 (20899 digits) lands in well under a second.
--
-- This version replaces the original's Data.Bits.bitSize with
-- bitWidth below. bitSize is deprecated in base (GHC 9.4 warns and
-- points at finiteBitSize) and absent from AHC's Data.Bits, and AHC
-- has a better reason than portability to avoid it: an AHC Int
-- PROMOTES to bignum on overflow rather than wrapping, so it has no
-- fixed width to report. Deriving the width from n itself is both
-- honest and shorter, and it drops the leading zeros the original
-- had to strip with `dropWhile not`.
--
-- The contract states the obligation the fold depends on. It cannot
-- fire, because main rejects negative input before calling fib -
-- validate at the boundary, assert inside, which is the Ada habit.
-- GHC ignores the pragmas, so this is ordinary portable Haskell and
-- the goldens in tests/ are GHC's output.

import Data.Bits (testBit)
import Data.List (foldl')
import System.Environment (getArgs)

--  How many bits n occupies: bitWidth 0 is 1, bitWidth 255 is 8.
bitWidth :: Int -> Int
bitWidth n = if n < 2 then 1 else 1 + bitWidth (n `div` 2)

{-# PRE  fib \n -> n >= 0 #-}
{-# POST fib \n r -> r >= 0 #-}
fib :: Int -> Integer
fib n = snd (foldl' step (1, 0) (bitsOf n))
  where
    bitsOf k = [testBit k i | i <- [bitWidth k - 1, bitWidth k - 2 .. 0]]
    step (f, g) p
      | p = (f * (f + 2 * g), ss)
      | otherwise = (ss, g * (2 * f - g))
      where
        ss = f * f + g * g

------------------------------------------------------------------
--  Driver
------------------------------------------------------------------

answer :: String -> String
answer s = case readIndex s of
  Nothing -> "error: not a number: '" ++ s ++ "'"
  Just n ->
    if n < 0
      then "error: fib is defined for n >= 0, got " ++ show n
      else show (fib n)

readIndex :: String -> Maybe Int
readIndex s = case s of
  ('-' : t) -> negateMaybe (readNat t)
  ('+' : t) -> readNat t
  _ -> readNat s

readNat :: String -> Maybe Int
readNat s =
  if null s || not (all isDigitChar s)
    then Nothing
    else Just (foldl' (\acc c -> acc * 10 + digitVal c) 0 s)

negateMaybe :: Maybe Int -> Maybe Int
negateMaybe m = case m of
  Nothing -> Nothing
  Just v -> Just (negate v)

isDigitChar :: Char -> Bool
isDigitChar c = c >= '0' && c <= '9'

digitVal :: Char -> Int
digitVal c = fromEnum c - fromEnum '0'

--  Blank lines and `--` comments are skipped, so a stdin script can
--  document itself.
runLine :: String -> [String]
runLine ln =
  let ws = words ln
  in if null ws || isComment ln then [] else map answer ws

isComment :: String -> Bool
isComment ln = case dropWhile (== ' ') ln of
  ('-' : '-' : rest) -> null rest || take 1 rest == " "
  _ -> False

main :: IO ()
main = do
  args <- getArgs
  if null args
    then getContents >>= \s -> putStr (unlines (concatMap runLine (lines s)))
    else putStr (unlines (map answer args))
