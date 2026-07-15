take' n (x : xs) = if n == 0 then [] else x : take' (n - 1) xs
take' _ [] = []
nats = [1 ..]
main = do
  print (take' 7 nats)
  print (take' 5 (map (* 10) nats))
  putStrLn (if length (take' 3 nats) == 3 then "lazy!" else "eager?")
