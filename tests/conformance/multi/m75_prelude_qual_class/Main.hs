module Main where
class Semigroup a where
  (<+>) :: a -> a -> a
newtype S = S Int deriving Show
instance Prelude.Semigroup S where S a <> S b = S (a + b)
instance Main.Semigroup S where S a <+> S b = S (a * b)
main :: IO ()
main = print (S 3 <> S 4, S 3 <+> S 4)
