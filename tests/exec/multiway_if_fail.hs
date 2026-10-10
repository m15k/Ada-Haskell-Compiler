{-# LANGUAGE MultiWayIf #-}
main :: IO ()
main = do
  putStrLn "before"
  print (if | False -> 1 :: Int)
