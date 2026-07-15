class Pretty a where
  pretty :: a -> String
  shout :: a -> String
  shout x = pretty x ++ "!"
data Light = Red | Amber | Green deriving (Eq, Ord)
instance Pretty Light where
  pretty Red = "red"
  pretty Amber = "amber"
  pretty Green = "green"
next c = if c == Green then Red else if c == Amber then Green else Amber
main = do
  putStrLn (shout Red)
  putStrLn (pretty (next Red))
  print (Red < Green)
  print (compare Amber Amber == EQ)
