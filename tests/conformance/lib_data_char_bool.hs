import Data.Char
import Data.Bool (bool)

main :: IO ()
main = do
  print (map toUpper "mixed Case 12!", map toLower "MIXED Case 12!")
  print (filter isAlpha "a1 B2_c", filter isAlphaNum "a1 B2_c")
  print (map isSpace " \ta", map isUpper "aBc", map isLower "aBc")
  print (map isHexDigit "09afAFgG", map isOctDigit "0789")
  print (map digitToInt "07af", map intToDigit [0, 7, 10, 15])
  print (ord 'A', chr 97)
  print (map (bool 0 1) [True, False, True])
  print (isPunctuation ',', isPunctuation 'a')
