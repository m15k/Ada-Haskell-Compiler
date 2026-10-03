module Main where
class C a where
  m :: a -> Name
instance C Bool where
  m b = if b then 1 else 0
type Name = Int
main :: IO ()
main = print (m True + 1)
