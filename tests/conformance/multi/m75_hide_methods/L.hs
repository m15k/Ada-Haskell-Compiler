module L where
class C a where c :: a -> String
instance C Int where c _ = "L"
