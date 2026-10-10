{-# LANGUAGE IncoherentInstances #-}
class C a where c :: a -> String
instance C [a] where c _ = "list"
instance C [Char] where c _ = "string"
g :: [b] -> String
g = c
main = do putStrLn (g "x"); putStrLn (c ("hi" :: String))
