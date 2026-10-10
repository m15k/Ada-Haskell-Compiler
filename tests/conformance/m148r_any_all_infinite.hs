main :: IO ()
main = do
  print (any (>3) [0..])
  print (all (<3) [0..])
  print (or (map (>3) [0..]))
  print (and (map (<3) [0..]))
  print (elem 5 [0..])
