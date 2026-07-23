import qualified Data.Map as Map

main :: IO ()
main = print (Map.size m, Map.foldrWithKey (\k _ a -> k + a) 0 m)
  where
    m = Map.fromList [(mod (i * 7919) 50021, i) | i <- [1 .. 40000 :: Int]]
