class S a where s :: a -> String; s2 :: a -> String
instance S a => S (Maybe a) where
  s _ = "m"
  s2 x = "<" ++ s x ++ ">"
instance {-# OVERLAPPING #-} S (Maybe Bool) where s _ = "mb"; s2 _ = "mb2"
instance S Int where s _ = "i"; s2 _ = "i"
main = putStrLn (s2 (Just (1::Int)))
