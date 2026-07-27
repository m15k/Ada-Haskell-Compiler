-- The thunk-protocol stress: many sparks racing the main task to
-- force one shared lattice of thunks (each layer references the
-- one below). Whoever wins each CAS, the updates agree - same
-- bytes every run, workers on or off.
import Control.Parallel

layer :: Int -> [Int]
layer 0 = [1 .. 200]
layer n = map (+ sum (take 3 (layer (n - 1)))) (layer (n - 1))

sparkAll :: [Int] -> Int -> Int
sparkAll xs r = foldr par r xs

main :: IO ()
main = do
  let l3 = layer 3
      l4 = layer 4
  print (sparkAll l4 (sum l3))
  print (sum l4)
  print (length (layer 5))
