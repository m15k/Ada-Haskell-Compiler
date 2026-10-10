class C a where c :: a -> String
instance C [Char] where c _ = "chars"
instance C [a] where c _ = "list"
newtype T a = T [a] deriving (C)
main :: IO ()
main = putStrLn (c (T "hi"))
