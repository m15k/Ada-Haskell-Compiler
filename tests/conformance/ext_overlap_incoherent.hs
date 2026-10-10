-- INCOHERENT lets a polymorphic use commit early (M148, GHC 9.4.8).
class C a where c :: a -> String
instance {-# INCOHERENT #-} C [a] where c _ = "list"
instance C [Char] where c _ = "string"
g :: [b] -> String
g x = c x
class E a where e :: a -> String
instance E [a] where e _ = "elist"
instance {-# OVERLAPPING #-} E [Bool] where e _ = "bools"
h :: E [b] => [b] -> String
h = e
main :: IO ()
main = mapM_ putStrLn [g "s", g [True], c "s", h [True], h "x", e [True]]
