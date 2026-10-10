{-# LANGUAGE DeriveFoldable #-}
data Str a = Cons a (Str a) deriving Foldable
data Sn a = Nil | Snoc (Sn a) a deriving Foldable
main :: IO ()
main = do
  print (null (Cons (1::Int) undefined))
  print (null (Snoc undefined (1::Int)))
