-- <<loop>> through a local alias pair (a = b, b = a): each thunk's
-- code returns the other thunk, the exact shape that would become an
-- indirection cycle under M146's evaluator if it did not check.
main :: IO ()
main = do
  let a = b :: Int
      b = a
  print (length [a, b])
  print a
