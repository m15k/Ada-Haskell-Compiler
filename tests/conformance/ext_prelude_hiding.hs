-- Report 5.6.1: an explicit "import Prelude hiding (...)" replaces
-- the implicit whole-Prelude import; the hidden name is free for a
-- module-local definition, and qualified access to names that are
-- NOT hidden still works through the same import.
import Prelude hiding (lookup)

lookup :: Int -> [(Int, String)] -> String
lookup _ [] = "?"
lookup k ((k', v) : rest) = if k == k' then v else lookup k rest

main :: IO ()
main = do
  putStrLn (lookup 2 [(1, "one"), (2, "two")])
  putStrLn (lookup 9 [(1, "one"), (2, "two")])
  Prelude.putStrLn "qualified access survives hiding"
