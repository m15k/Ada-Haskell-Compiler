class C a where c :: a -> String
instance C a where c _ = "any"
main :: IO ()
main = putStrLn (c undefined)
