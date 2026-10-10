class C a where c :: a -> String
instance {-# overlappable #-} C [a] where c _ = "list"
instance C [Char] where c _ = "string"
main = do putStrLn (c [True]); putStrLn (c "hi")
