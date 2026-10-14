import Control.Exception
t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))
main :: IO ()
main = do
  t ((
     !! 2) [1::Int])
  t (( {- c -} !! 3) [1::Int])
  t ((-- c
      !! 4) [1::Int])
  t (([1::Int] {- x -}
      !!) 5)
  t (([1::Int]) `seq` (!! 6) [])
