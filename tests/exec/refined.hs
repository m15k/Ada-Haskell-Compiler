type Digit = Int in 0 .. 9

clamp :: Int -> Digit
clamp n = if n < 0 then 0 else if n > 9 then 9 else n

double :: Digit -> Int
double d = d + d

countdown :: Digit -> [Int]
countdown n = if n <= 0 then [0] else n : countdown (n - 2)

lazily :: Int -> Digit
lazily n = n

main :: IO ()
main = do
  print (double (clamp 15))
  print (double (clamp (-4)))
  let unused = lazily 99 in print (const True unused)
  print ((7 :: Digit) - 3)
  print (countdown 8)
  print (countdown 7)
