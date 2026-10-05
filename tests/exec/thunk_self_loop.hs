-- <<loop>> through a local self-reference: since M146 the evaluator
-- updates a thunk to an indirection before forcing its result, and
-- must still report the cycle rather than spin on it (GHC prints 1,
-- then dies with <<loop>>; AHC's banner is ahc:, EXCLUSIONS 9).
main :: IO ()
main = do
  let x = x + 1 :: Int
  print (length [x])
  print x
