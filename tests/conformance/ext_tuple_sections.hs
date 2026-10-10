{-# LANGUAGE TupleSections #-}
-- TupleSections, always on in AHC (M148), oracled against GHC 9.4.8.
main :: IO ()
main = do
  print (map (,True) [1, 2 :: Int], map (1 :: Int,) "ab")
  print (zipWith3 (,,) [1 :: Int] "x" [True], map (,"x",) [1 :: Int, 2] <*> [False])
  print ((, 'b', ) 'a' 'c', fmap (0 :: Int,) (Just "j"), (,,5 :: Int) 'p' 'q')
  print ((1 :: Int, 2 :: Int), (,) 'x' 'y')
