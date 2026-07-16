factorial :: Integer -> Integer
factorial n = if n <= 1 then 1 else n * factorial (n - 1)

main :: IO ()
main = do
  print (product [1 .. 25])
  print (factorial 30)
  print (2 ^^^ 100)
  print 123456789012345678901234567890
  print (-123456789012345678901234567890)
  print (123456789012345678901234567890 + 1)
  print (div (factorial 30) (factorial 28), mod (factorial 30) 7)
  print (div (-123456789012345678901234567890) 7)
  print (mod (-123456789012345678901234567890) 7)
  print (quot (-123456789012345678901234567890) 7)
  print (rem (-123456789012345678901234567890) 7)
  print (factorial 20 == product [1 .. 20])
  print (compare (2 ^^^ 64) (2 ^^^ 63), 2 ^^^ 64 > 0)
  print (Just (2 ^^^ 70))
  print (map (* 1000000000000000000) [9, -9])
  print (fromInteger 123456789012345678901234567890 / 1.0e29)
  where
    (^^^) :: Integer -> Int -> Integer
    b ^^^ e = if e == 0 then 1 else b * (b ^^^ (e - 1))
