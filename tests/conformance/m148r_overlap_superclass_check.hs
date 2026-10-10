class B a where b :: a -> String
class B a => C a where c :: a -> String
instance {-# OVERLAPPABLE #-} B [a] where b _ = "Blist"
instance B [Char] where b _ = "Bstring"
instance {-# OVERLAPPABLE #-} C [a] where c _ = "Clist"
instance C [Char] where c _ = "Cstring"
h :: C a => a -> String
h x = b x ++ c x
main = do putStrLn (h "x"); putStrLn (h [True])
