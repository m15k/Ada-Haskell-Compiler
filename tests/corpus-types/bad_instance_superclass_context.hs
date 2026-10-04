-- The superclass instance exists but needs a context the instance does
-- not give: Eq (T a) requires Eq a, and `instance Ord (T a)` provides
-- nothing. GHC: "No instance for (Eq a) arising from the superclasses".
data T a = T a

instance Eq a => Eq (T a) where
  T a == T b = a == b

instance Ord (T a) where
  compare _ _ = EQ

main :: IO ()
main = print (compare (T 'a') (T 'b'))
