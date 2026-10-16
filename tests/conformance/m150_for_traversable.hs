-- M150 phase C: Data.Traversable (for, forM, mapAccumL, mapAccumR)
-- and Control.Monad's forM/forM_ over any Traversable/Foldable.
import Control.Monad (forM, forM_)
import Data.Traversable (for, mapAccumL, mapAccumR)
import qualified Data.Traversable as T
import qualified Data.Map as M

main :: IO ()
main = do
  r <- forM (Just 5) (\x -> print x >> return (x * 2 :: Int))
  print r
  forM_ (Just 'q') print
  forM_ (Nothing :: Maybe Int) print
  forM_ (M.fromList [(2, "two"), (1, "one")]) putStrLn
  xs <- forM [1, 2, 3 :: Int] (\x -> return (x * x))
  print xs
  print (for [1, 2, 3 :: Int] (\x -> if x > 0 then Just x else Nothing))
  print (T.forM (Right 4 :: Either String Int) (\x -> [x, x + 1]))
  print (T.traverse (\x -> [x]) (Just 'c'))
  print (mapAccumL (\acc x -> (acc + x, acc * x)) 0 [1, 2, 3 :: Int])
  print (mapAccumR (\acc x -> (acc + x, acc * x)) 0 [1, 2, 3 :: Int])
  print (mapAccumL (\n c -> (n + 1, (n, c))) (0 :: Int) (Just 'z'))
  print (mapAccumL (\acc v -> (acc ++ v, length acc))
                   "" (M.fromList [(1 :: Int, "ab"), (2, "c")]))
  print (T.sequenceA [Just 1, Just (2 :: Int)])
  print (T.mapM (\x -> if x > 1 then Right x else Left x) [2, 3, 1 :: Int])
