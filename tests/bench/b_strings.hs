-- String-literal and [Char] traffic: repeated literal use inside a
-- hot loop (the per-evaluation rebuild cost that literal CAF
-- hoisting removes), plus ++/lines/words/show consumption.
main :: IO ()
main = print (go 10000 0)
  where
    go :: Int -> Int -> Int
    go 0 acc = acc
    go n acc =
      let s = "the quick brown fox jumps over the lazy dog, "
                ++ show n
          w = length (words s)
          l = length (lines ("a\nb\nc\n" ++ s))
      in go (n - 1) (acc + length s + w + l)
