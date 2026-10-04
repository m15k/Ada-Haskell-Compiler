-- Report 9: names the Prelude exports that AHC used to keep in lib/ or
-- lacked (M144b): the zip/scan families, writeFile/appendFile, (=<<),
-- ShowS/ReadS/showChar, asTypeOf, foldMap, errorWithoutStackTrace and
-- the inverse hyperbolics - all with NO import.
import Control.Exception (ErrorCall (..), evaluate, try)

newtype Sum' = Sum' Int deriving Show

instance Semigroup Sum' where
  Sum' a <> Sum' b = Sum' (a + b)

instance Monoid Sum' where
  mempty = Sum' 0

data Tree a = Leaf | Node (Tree a) a (Tree a)

instance Foldable Tree where
  foldr _ z Leaf = z
  foldr f z (Node l x r) = foldr f (f x (foldr f z r)) l

-- an instance that gives foldMap, not foldr, would need foldr's
-- default; here foldMap's own default over foldr is exercised.
render :: Int -> ShowS
render n = showChar '<' . shows n . showChar '>'

readsInt :: ReadS Int
readsInt s = [(n, r) | (n, r) <- reads s]

main :: IO ()
main = do
  print (scanl (+) 0 [1, 2, 3, 4 :: Int])
  print (scanl1 max [3, 1, 4, 1, 5 :: Int])
  print (scanr (+) 0 [1, 2, 3 :: Int])
  print (scanr1 (-) [10, 4, 3 :: Int])
  print (take 5 (scanl (+) 0 [1 :: Int ..]))
  print (zip3 [1 :: Int, 2, 3] "ab" [True, False, True])
  print (unzip3 [(1 :: Int, 'a', True), (2, 'b', False)])
  print (zipWith3 (\a b c -> a + b * c) [1, 2, 3] [4, 5, 6] [7, 8, 9 :: Int])
  print (Just 3 >>= \x -> Just (x + 1 :: Int))
  print ((\x -> [x, x * 10]) =<< [1, 2, 3 :: Int])
  putStrLn (render 42 "!")
  print (readsInt "17 rest")
  print (asTypeOf 3 (4 :: Int))
  print (foldMap (\x -> Sum' x) [1, 2, 3, 4])
  print (foldMap (\x -> [x, x]) (Node (Node Leaf 1 Leaf) (2 :: Int) (Node Leaf 3 Leaf)))
  r <- try (evaluate (errorWithoutStackTrace "boom" :: Int))
  case r of
    Left (ErrorCall m) -> putStrLn ("caught " ++ m)
    Right _ -> putStrLn "no error"
  print (asinh 0 :: Double, acosh 1 :: Double, atanh 0 :: Double)
  let path = "/tmp/ahc_ch09_prelude_additions.tmp"
  writeFile path "one\n"
  appendFile path "two\n"
  s <- readFile path
  putStr s
  print (length (lines s))
