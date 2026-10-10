class C a where c :: a -> String
instance C (Maybe Int) where c _ = "mi"
main :: IO ()
main = putStrLn (go (1 :: Int))
  where go x = c (Just x)
