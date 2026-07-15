class Pretty a where
  pretty :: a -> String
  shout :: a -> String
  shout x = pretty x ++ "!"
instance Pretty Bool where
  pretty b = if b then "yes" else "no"
data B a = B a
instance Pretty a => Pretty (B a) where
  pretty (B x) = pretty x
main = putStrLn (pretty (B True))
