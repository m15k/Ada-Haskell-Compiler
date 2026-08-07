import Data.Char
-- One checksum per function over every code point: any single
-- disagreement with GHC changes the sum.
sumP :: (Char -> Bool) -> Int
sumP p = go 0 0
  where go acc c = if c > 0x10FFFF then acc
                   else let acc' = if p (toEnum c) then acc + c else acc
                        in seq acc' (go acc' (c + 1))
sumM :: (Char -> Char) -> Int
sumM f = go 0 0
  where go acc c = if c > 0x10FFFF then acc
                   else let acc' = acc + fromEnum (f (toEnum c))
                        in seq acc' (go acc' (c + 1))
main :: IO ()
main = do
  print (sumP isUpper, sumP isLower, sumP isAlpha)
  print (sumP isAlphaNum, sumP isPunctuation, sumP isSpace)
  print (sumM toUpper, sumM toLower)
