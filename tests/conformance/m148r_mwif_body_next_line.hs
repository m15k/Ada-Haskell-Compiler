{-# LANGUAGE MultiWayIf #-}
main :: IO ()
main = do
  let x = 3 :: Int
  putStrLn $ if | x > 5 -> "a"
                | otherwise ->
                "c"
