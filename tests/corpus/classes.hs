module C where
class Show a => Pretty a where
  pretty :: a -> String
  pretty = show
instance Pretty Int
instance Pretty a => Pretty [a] where
  pretty xs = concat [ pretty x | x <- xs ]
default (Int)
