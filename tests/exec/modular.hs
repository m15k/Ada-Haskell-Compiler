type Clock = Int mod 12
type Byte = Int mod 256

shift :: Clock -> Int -> Clock
shift t d = t + d

inc :: Byte -> Byte
inc b = b + 1

chain :: Clock -> Clock
chain t = shift (shift t 10) 10

main :: IO ()
main = do
  print (shift 9 5)
  print (shift 3 (-7))
  print ((25 :: Clock))
  print (inc 255)
  print (chain 11)
  print (map (`mod` 3) [1, 2, 3, 4])
