-- A string literal consumed by a polymorphic function: the literal's
-- element type is fixed by IsString's list rule, and every OTHER
-- constraint on that element (Show, Eq, Ord) must still be solved
-- afterwards. Attempting them once, before the element was known,
-- and never retrying is how `reverse "abc"` shipped a $dMISSING
-- into a compiled program.
import Data.List (sort, nub)

main :: IO ()
main = do
  print (reverse "abc")
  print (map id "abc")
  print (sort (nub "abracadabra"))
  print (maximum "abc")
  print (concat ["ab", "cd"])
  print (zip "ab" [1 :: Int, 2])
  putStrLn (unwords (words "a b c"))
