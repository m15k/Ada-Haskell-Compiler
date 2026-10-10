class C a where c :: a -> String
instance C (Maybe Int) where c _ = "mi"
instance C (Maybe Bool) where c _ = "mb"
h :: C (Maybe a) => a -> String
h x = c (Just x)
main :: IO ()
main = putStrLn (h (1::Int) ++ h True)
