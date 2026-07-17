import Control.Monad
import Data.Functor ((<$>), ($>))

halve :: Int -> Maybe Int
halve n = if even n then Just (div n 2) else Nothing

main :: IO ()
main = do
  when True (putStrLn "when fires")
  unless True (putStrLn "never")
  print (mapM halve [2, 4, 8], mapM halve [2, 3])
  print (sequence [Just 1, Just 2], sequence [Just 1, Nothing])
  print ((halve >=> halve) 8, (halve <=< halve) 12)
  print (join (Just (Just 5)), join [[1, 2], [3]])
  print (filterM (\x -> Just (x > 1)) [1, 2, 3])
  print (foldM (\a x -> Just (a + x)) 0 [1, 2, 3])
  print (liftM2 (+) (Just 3) (Just 4), ap (Just negate) (Just 7))
  print (fmap (* 2) (Just 21), (* 2) <$> [1, 2, 3])
  print (Just 1 $> "replaced")
  r <- replicateM 3 (return 7)
  print r
  xs <- mapM (\x -> return (x * x)) [1, 2, 3]
  print xs
  zipWithM_ (\a b -> print (a + b)) [1, 2] [10, 20]
