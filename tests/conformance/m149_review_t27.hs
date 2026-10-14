import Control.Exception
t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))
main :: IO ()
main = t (f 3)
f :: Int -> Int
f 1 = 1
f 2 = 2