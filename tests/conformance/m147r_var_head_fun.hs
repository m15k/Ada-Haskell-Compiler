class C a where c :: a -> String
instance C (f a) where c _ = "app"
main :: IO ()
main = do
  putStrLn (c (Just 'x'))
  putStrLn (c not)
