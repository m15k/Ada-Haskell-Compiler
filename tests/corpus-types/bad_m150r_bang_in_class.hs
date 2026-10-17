module Main where
class C a where
  cc :: a -> Int
  !cc = \_ -> 1
instance C Bool
main :: IO ()
main = print (cc True)
