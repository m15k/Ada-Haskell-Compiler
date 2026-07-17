module Data.Char
  ( ord, chr
  , isUpper, isLower, isAlpha, isDigit, isAlphaNum, isSpace
  , isHexDigit, isOctDigit, isPunctuation
  , toUpper, toLower
  , digitToInt, intToDigit
  ) where

isUpper :: Char -> Bool
isUpper c = c >= 'A' && c <= 'Z'

isLower :: Char -> Bool
isLower c = c >= 'a' && c <= 'z'

isAlpha :: Char -> Bool
isAlpha c = isUpper c || isLower c

isDigit :: Char -> Bool
isDigit c = c >= '0' && c <= '9'

isAlphaNum :: Char -> Bool
isAlphaNum c = isAlpha c || isDigit c

isSpace :: Char -> Bool
isSpace c = c == ' ' || c == '\t' || c == '\n' || c == '\r'
         || c == '\f' || c == '\v'

isHexDigit :: Char -> Bool
isHexDigit c = isDigit c || (c >= 'a' && c <= 'f')
            || (c >= 'A' && c <= 'F')

isOctDigit :: Char -> Bool
isOctDigit c = c >= '0' && c <= '7'

isPunctuation :: Char -> Bool
isPunctuation c = elem c "!\"#%&'()*,-./:;?@[\\]_{}"

toUpper :: Char -> Char
toUpper c = if isLower c then chr (ord c - 32) else c

toLower :: Char -> Char
toLower c = if isUpper c then chr (ord c + 32) else c

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
