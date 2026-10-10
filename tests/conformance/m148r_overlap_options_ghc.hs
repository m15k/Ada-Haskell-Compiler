{-# OPTIONS_GHC -XOverlappingInstances #-}
class C a where c :: a -> String
instance C [a] where c _ = "list"
instance C [Char] where c _ = "string"
main = do putStrLn (c [True]); putStrLn (c ("hi" :: String))
