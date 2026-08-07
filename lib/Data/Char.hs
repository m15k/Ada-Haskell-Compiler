module Data.Char
  ( ord, chr
  , isUpper, isLower, isAlpha, isDigit, isAlphaNum, isSpace
  , isHexDigit, isOctDigit, isPunctuation
  , toUpper, toLower
  , digitToInt, intToDigit
  ) where

-- Classification and case mapping are UNICODE-aware, backed by
-- tables generated from the oracle GHC's own Data.Char
-- (tests/gen_unicode.hs -> runtime/ahc_unicode.h), so agreement is
-- by construction. The digit predicates stay ASCII, as in GHC.

isUpper :: Char -> Bool
isUpper = primIsUpperU

isLower :: Char -> Bool
isLower = primIsLowerU

isAlpha :: Char -> Bool
isAlpha = primIsAlphaU

isDigit :: Char -> Bool
isDigit c = c >= '0' && c <= '9'

isAlphaNum :: Char -> Bool
isAlphaNum = primIsAlphaNumU

isSpace :: Char -> Bool
isSpace = primIsSpaceU

isHexDigit :: Char -> Bool
isHexDigit c = isDigit c || (c >= 'a' && c <= 'f')
            || (c >= 'A' && c <= 'F')

isOctDigit :: Char -> Bool
isOctDigit c = c >= '0' && c <= '7'

isPunctuation :: Char -> Bool
isPunctuation = primIsPunctuationU

toUpper :: Char -> Char
toUpper = primToUpperU

toLower :: Char -> Char
toLower = primToLowerU

digitToInt :: Char -> Int
digitToInt c
  | isDigit c            = ord c - ord '0'
  | c >= 'a' && c <= 'f' = ord c - ord 'a' + 10
  | c >= 'A' && c <= 'F' = ord c - ord 'A' + 10
  | otherwise            = error "Char.digitToInt: not a digit"

intToDigit :: Int -> Char
intToDigit n
  | n >= 0 && n <= 9   = chr (ord '0' + n)
  | n >= 10 && n <= 15 = chr (ord 'a' + n - 10)
  | otherwise          = error "Char.intToDigit: not a digit"
