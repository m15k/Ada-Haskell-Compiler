main :: IO ()
main = do
  let b = 2 ^ (70 :: Int) :: Integer
  print [b .. b + 2]
  print (take 3 [b ..], take 3 [b, b + 5 ..], [b, b - 3 .. b - 10])
  print (succ b, pred (negate b), [b + 2, b + 1 .. b])
  print (take 3 [9223372036854775806 :: Integer ..])
  print ([1 .. 0] :: [Integer], [3, 3 .. 2] :: [Integer], take 3 [3, 3 .. 4] :: [Integer])
  print (take 2 [10 ^ (30 :: Int), 10 ^ (30 :: Int) * 2 ..] :: [Integer])
  print (fromEnum (12345 :: Integer), toEnum 7 :: Integer, fromEnum b)
  print (sum [1 .. 100000 :: Integer], length [b .. b + 99999])
