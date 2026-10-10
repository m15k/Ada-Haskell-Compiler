{-# LANGUAGE UndecidableInstances #-}
-- OVERLAPPING / OVERLAPPABLE / OVERLAPS (M148): the most specific
-- instance wins when the others allow it, as in GHC 9.4.8.
class C a where c :: a -> String
instance {-# OVERLAPPABLE #-} C [a] where c _ = "list"
instance C [Char] where c _ = "string"
instance {-# OVERLAPPING #-} C (Maybe Int) where c _ = "maybe-int"
instance C (Maybe a) where c _ = "maybe"

class D a where d :: a -> String
instance {-# OVERLAPS #-} D a where d _ = "any"
instance {-# OVERLAPS #-} D [a] where d _ = "list"
instance {-# OVERLAPS #-} D [Int] where d _ = "ints"

class Pretty a where pretty :: a -> String
instance {-# OVERLAPPABLE #-} Show a => Pretty a where pretty = show
instance Pretty String where pretty s = s

main :: IO ()
main = do
  mapM_ putStrLn [c [True], c "s", c (Just (1 :: Int)), c (Just 'x')]
  mapM_ putStrLn [d True, d "xy", d [1 :: Int], d [True]]
  putStrLn (pretty (3 :: Int) ++ " " ++ pretty "plain" ++ " " ++ pretty [True])
