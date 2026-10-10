{-# LANGUAGE DeriveFoldable #-}
data Tree a = Leaf | Node (Tree a) a (Tree a) deriving Foldable
main :: IO ()
main = print (null (Node undefined (1::Int) undefined))
