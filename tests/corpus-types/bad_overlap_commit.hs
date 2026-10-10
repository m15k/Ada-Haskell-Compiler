-- A polymorphic use cannot commit to the list instance while the
-- String instance might still match (GHC 9.4.8 rejects this).
class C a where c :: a -> String
instance {-# OVERLAPPABLE #-} C [a] where c _ = "list"
instance C [Char] where c _ = "string"
g :: [b] -> String
g x = c x
main :: IO ()
main = putStrLn (g [True])
