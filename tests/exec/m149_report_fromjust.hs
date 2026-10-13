-- M149: fromJust Nothing, located at the use.
import Data.Maybe (fromJust)

main :: IO ()
main = do
  let m = lookup "b" [("a", 1 :: Int)]
  print (fromJust m)
