module Main where
data Either a b = Lft a | Rgt b deriving Show
f :: Prelude.Either Int Bool -> String
f (Prelude.Left n) = "left " ++ show n
f (Prelude.Right b) = "right " ++ show b
main :: IO ()
main = putStrLn (f (Prelude.Left 3)) >> print (Lft 1 :: Main.Either Int Int)
