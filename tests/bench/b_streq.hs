-- Eq/Ord on String and [Int] (M150): the list instance must keep
-- choosing the structural primitive when its elements' instances are
-- structural, so this costs what it cost before structural
-- dictionaries.
main :: IO ()
main = print (go 20000 0)
  where
    ws = words "the quick brown fox jumps over the lazy dog"
    go :: Int -> Int -> Int
    go 0 acc = acc
    go n acc =
      let s = show (n `mod` 97)
          xs = [n `mod` 7, 2, 3 :: Int]
          a = length (filter (== "fox") ws) + length (filter (< s) ws)
          b = if xs == [3, 2, 3] then 1 else 0
          c = if compare [s] ["5"] == LT then 1 else 0
      in go (n - 1) (acc + a + b + c)
