{-# LANGUAGE LambdaCase #-}
class C a where
  f :: a -> Int
  f = \case _ -> 0
instance C Bool
instance C Int where { f = \case 0 -> 1; _ -> 2 }
main :: IO ()
main = print (f True, f (0::Int), f (5::Int))
