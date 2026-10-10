{-# LANGUAGE MultiWayIf #-}
main :: IO ()
main = do
  let x = 3 :: Int
  print $ if | x > 0
             , x < 5 -> "range"
             | otherwise -> "out"
