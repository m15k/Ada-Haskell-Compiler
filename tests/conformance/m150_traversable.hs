-- M150 phase C: mapM, sequence, traverse and sequenceA are Traversable
-- methods over every container base gives an instance (GHC 9.4.8).
import qualified Data.Map as M
import Data.Array (listArray)
import Data.Functor.Identity (Identity (..))

data Tree a = Leaf | Node (Tree a) a (Tree a)
  deriving Show

instance Functor Tree where
  fmap _ Leaf = Leaf
  fmap f (Node l x r) = Node (fmap f l) (f x) (fmap f r)

instance Foldable Tree where
  foldr _ z Leaf = z
  foldr f z (Node l x r) = foldr f (f x (foldr f z r)) l

instance Traversable Tree where
  traverse _ Leaf = pure Leaf
  traverse f (Node l x r) = Node <$> traverse f l <*> f x <*> traverse f r

positive :: Int -> Maybe Int
positive x = if x > 0 then Just x else Nothing

checked :: Int -> Either String Int
checked x = if x > 0 then Right x else Left ("bad " ++ show x)

tree :: Tree Int
tree = Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf)

main :: IO ()
main = do
  -- Maybe as the container
  print (mapM positive (Just 3))
  print (mapM positive (Nothing :: Maybe Int))
  print (sequence (Just [1, 2 :: Int]))
  print (sequenceA (Just (Right 'x' :: Either String Char)))
  r <- mapM (\x -> print x >> return (x * 2)) (Just (21 :: Int))
  print r
  -- Either as the container and as the effect
  print (mapM checked [1, 2, -3, 4])
  print (mapM checked [1, 2, 3])
  print (sequence (Right (Just 3) :: Either String (Maybe Int)))
  print (traverse positive (Left "no" :: Either String Int))
  -- Map: values in key order
  let m = M.fromList [(3, 30), (1, 10), (2, 20 :: Int)]
  print (traverse positive m)
  print (mapM positive (M.insert 4 0 m))
  _ <- mapM print m
  print (sequence (M.fromList [(1 :: Int, [1, 2 :: Int]), (2, [3])]))
  -- a user Traversable
  print (traverse positive tree)
  print (mapM (\x -> [x, x * 10]) (Node Leaf 1 (Node Leaf 2 Leaf)))
  print (sequenceA (fmap Just tree))
  print (sum tree, length tree, maximum tree)
  -- pairs: Functor, Foldable and Traversable over the second component
  print (fmap (+ 1) ("k", 1 :: Int))
  print (length ("k", 'x'), sum ((), 5 :: Int), elem 'x' (True, 'x'))
  print (traverse (\x -> [x, x + 1]) ("k", 1 :: Int))
  print (sequence ('a', Just True))
  print (mapM positive (0 :: Int, -1))
  -- Identity
  print (runIdentity (traverse (Identity . (* 2)) [1, 2, 3 :: Int]))
  print (traverse (\x -> [x, negate x]) (Identity (3 :: Int)))
  print (sum (Identity (7 :: Int)), fmap show (Identity True))
  -- Array: Functor, Foldable, Traversable
  let a = listArray (0, 2) [1, 2, 3 :: Int]
  print (fmap (* 2) a)
  print (sum a, length a, maximum a)
  print (traverse positive a)
  print (mapM positive (fmap (subtract 2) a))
  -- lists still work, effects in order
  xs <- mapM (\x -> putStrLn ("visit " ++ show x) >> return (x + 1)) [1, 2, 3 :: Int]
  print xs
  ys <- sequence [return 'a', return 'b']
  putStrLn ys
  -- a string literal (OverloadedStrings is unconditional in AHC)
  mapM (\c -> return (succ c)) "abc" >>= putStrLn
