class C a where c :: a -> String
instance {-# INCOHERENT #-} C [a] where c _ = "list"
instance C [Char] where c _ = "string"
f :: C [a] => [a] -> String
f x = c x
main = do putStrLn (f "x"); putStrLn (f ['x']); let s = "y" in putStrLn (f s)
