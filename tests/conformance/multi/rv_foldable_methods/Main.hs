data B a = B a a
instance Foldable B where
  foldr f z (B a b) = f a (f b z)
  foldr1 f (B a b) = f a b
main = print (foldr1 (+) (B 1 (2::Int)))
