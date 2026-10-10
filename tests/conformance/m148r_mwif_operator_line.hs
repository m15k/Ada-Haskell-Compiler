{-# LANGUAGE MultiWayIf #-}
main :: IO ()
main = do
  let x = 3 :: Int
  print $ if | x > 5 -> "a"
             | x > 1 -> "b"
             ++ "!"
             | otherwise -> "c"
