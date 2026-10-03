module Main where
class C a where
  m :: a -> T
instance C Bool where
  m _ = T
data T = T deriving Show
main :: IO ()
main = print (m True)
