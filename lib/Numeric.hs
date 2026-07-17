module Numeric
  ( showHex, showOct, showIntAtBase
  , readHex, readOct, readDec
  ) where

import Data.Char (intToDigit, digitToInt, isDigit, isHexDigit,
                  isOctDigit)

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
