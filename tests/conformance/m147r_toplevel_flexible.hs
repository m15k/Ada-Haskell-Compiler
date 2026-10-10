class C a where c :: a -> String
instance C [Char] where c _ = "chars"
instance C [Bool] where c _ = "bools"
g x = c [x]
main :: IO ()
main = do
  putStrLn (g 'a')
  putStrLn (g True)
