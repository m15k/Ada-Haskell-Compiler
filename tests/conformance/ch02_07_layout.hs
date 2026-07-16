-- Report 2.7 / 10.3: the layout algorithm across where/let/do/case.
f :: Int -> Int
f x = a + b
  where
    a = x * 2
    b = let c = a + 1
            d = c + 1
        in c + d

g :: Int -> Int
g n = case n of
        0 -> 10
        _ -> n

main :: IO ()
main = do
  print (f 3)
  let h = g
  print (h 0)
  print (h 7)
