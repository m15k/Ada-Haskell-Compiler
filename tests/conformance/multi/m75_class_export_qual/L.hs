module L where
class Named a where name :: a -> String
instance Named Int where name n = "L" ++ show n
