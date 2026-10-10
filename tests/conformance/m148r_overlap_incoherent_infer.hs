class C a where c :: a -> String
instance {-# INCOHERENT #-} C [a] where c _ = "list"
instance C [Char] where c _ = "string"
k x = c [x]
main = do putStrLn (k 'x'); putStrLn (k True)
