class C a where c :: a -> String
instance C [Char] where c _ = "chars"
instance C [b] where c _ = "list"
f :: [a] -> String
f = c
main :: IO ()
main = do
  putStrLn (f "hi")
  putStrLn (c "hi")
