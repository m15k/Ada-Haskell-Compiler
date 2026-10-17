module Main where
class C a where
  cc :: a -> Int
instance C Bool where
  !cc = \_ -> 2
main :: IO ()
main = print (cc True)
