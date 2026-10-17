{-# LANGUAGE GeneralizedNewtypeDeriving #-}
import Data.Char (toLower)
newtype Ci = Ci String deriving Show
instance Eq Ci where Ci a == Ci b = map toLower a == map toLower b
instance Ord Ci where compare (Ci a) (Ci b) = compare (map toLower a) (map toLower b)
newtype Wr = Wr Ci deriving (Show, Eq, Ord)
newtype Wp a = Wp a deriving (Show, Eq, Ord)
data D = D Ci deriving (Show, Eq, Ord)
main = do
  print (max (Ci "A") (Ci "a"), min (Ci "A") (Ci "a"))
  print (max (Wr (Ci "A")) (Wr (Ci "a")), min (Wr (Ci "A")) (Wr (Ci "a")))
  print (max (Wp (Ci "A")) (Wp (Ci "a")), min (Wp (Ci "A")) (Wp (Ci "a")))
  print (max (Wp 0.0) (Wp (-0.0 :: Double)), min (Wp 0.0) (Wp (-0.0 :: Double)))
  print (max (D (Ci "A")) (D (Ci "a")), min (D (Ci "A")) (D (Ci "a")))
  print (maximum [Ci "A", Ci "a"], minimum [Ci "A", Ci "a"], maximum [Wr (Ci "A"), Wr (Ci "a")])
