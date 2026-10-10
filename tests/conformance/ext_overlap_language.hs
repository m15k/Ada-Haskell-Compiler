{-# LANGUAGE OverlappingInstances #-}
-- The deprecated module pragma marks every instance OVERLAPS (M148).
class C a where c :: a -> String
instance C [a] where c _ = "list"
instance C [Char] where c _ = "string"
instance C a where c _ = "any"
main :: IO ()
main = mapM_ putStrLn [c "s", c [True], c 'x']
