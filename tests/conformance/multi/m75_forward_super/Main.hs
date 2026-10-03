module Main where
class Base a => Derived a where
  dv :: a -> Int
class Base a where
  bv :: a -> Int
instance Base Bool where
  bv _ = 10
instance Derived Bool where
  dv _ = 1
both :: Derived a => a -> Int
both x = dv x + bv x
main :: IO ()
main = print (both True)
