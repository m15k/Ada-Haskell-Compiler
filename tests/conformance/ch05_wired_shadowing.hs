-- Report ch. 5: a library or user module re-defining a name that
-- the wired Prelude also owns must not disturb OTHER modules'
-- references to the Prelude one. Found by the REPL's first
-- session (M80): with Data.Map imported, Data.List's nub died on
-- a missing global - Data.Map's filter had stolen the wired
-- filter's body slot in the name-keyed install table.
import Data.List (sort, nub)
import Data.Map (fromList, toList)

filter :: Int -> Int
filter x = x + 1

main :: IO ()
main = do
  print (sort (nub "abracadabra"))
  print (toList (fromList [(2 :: Int, "two"), (1, "one")]))
  print (Prelude.filter even [1 .. 8 :: Int])
  print (Data.Map.toList (Data.Map.fromList [(True, 'a')]))
