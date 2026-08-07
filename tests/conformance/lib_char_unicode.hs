-- Data.Char is Unicode-aware (tables generated from the oracle
-- GHC itself); the digit predicates stay ASCII, as in GHC. The
-- companion lib_char_unicode_sums.hs checksums EVERY code point.
import Data.Char

main :: IO ()
main = do
  print (map toUpper "h\233llo \955 gro\223")
  print (map toLower "\923\902\924\914\916\913")
  print (map isAlpha "a\955\28450\178 _")
  print (map isUpper "A\196\923a", map isLower "a\228\955A")
  print (isSpace '\160', isSpace '\8239', isSpace '\8203')
  print (map isPunctuation "!\191\8212\171")
  print (isAlphaNum '\178', isAlphaNum '\189')
  print (words "a\tb\160c d")
  print (isDigit '\1635', digitToInt 'f', intToDigit 11)
