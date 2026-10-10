{-# LANGUAGE MultiWayIf #-}
-- MultiWayIf, always on in AHC (M148), oracled against GHC 9.4.8.
classify :: Int -> String
classify x = if | x < 0 -> "negative"
                | x == 0 -> "zero"
                | even x, x > 100 -> "big even"
                | otherwise -> if | odd x -> "odd" | otherwise -> "even"

grade :: Int -> Char
grade s =
  if
    | s >= 90 -> 'A'
    | s >= 80 -> 'B'
    | Just t <- lookup s [(42, 'Z')] -> t
    | otherwise -> 'F'

main :: IO ()
main = do
  mapM_ (putStrLn . classify) [-3, 0, 102, 7, 8]
  putStrLn (map grade [95, 85, 42, 10])
  let y = 5 :: Int
  print (if | y > 3 -> "gt" | otherwise -> "le", if | True -> 1 :: Int)
  where _unused = ()
