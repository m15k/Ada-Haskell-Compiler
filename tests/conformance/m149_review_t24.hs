{-# LANGUAGE EmptyCase, MultiWayIf #-}
import Control.Exception
t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))
ec :: Int -> Bool
ec n = case n of {}
main :: IO ()
main = do
  t (ec 3)
  t (if | False -> 'a')
  t (let f x | x > (2::Int) = if | x > 5 -> 'b' in f 3)
  t ((\x -> if | x -> 'c') False)
