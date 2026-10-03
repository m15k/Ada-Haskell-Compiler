module Main where
class Nope a => D a where
  d :: a -> Int
instance D Bool where
  d _ = 1
main :: IO ()
main = print (d True)
