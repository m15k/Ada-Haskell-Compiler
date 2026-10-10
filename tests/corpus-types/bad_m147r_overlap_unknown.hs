class C a where c :: a -> String
instance C [Char] where c _ = "chars"
main :: IO ()
main = putStrLn (c [])
