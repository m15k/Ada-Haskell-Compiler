import Control.Exception
t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))
main :: IO ()
main = t (f 3) >> t (g 3)
g :: Int -> Int
g n = case n of
  1 -> 2 -- c
f :: Int -> Int
f 1 = 1
f 2 = case 3 of
  3 -> 4 -- z