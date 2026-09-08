-- A case with a VARIABLE alternative over a class-constrained
-- scrutinee: the scrutinee's constraint must follow the bound
-- variable's type, not be defaulted on its own. The desugarer binds
-- the scrutinee in a monomorphic let; the typechecker must keep that
-- let's type variables at the enclosing level, or the sibling
-- binding for the alternative's variable generalizes over them (the
-- M138 adversarial review found 3.5 printed as 2.0e-323).
half :: Int -> Double
half n = case fromIntegral n of d -> d / 2

avg :: [Int] -> Double
avg xs = case fromIntegral (sum xs) of s -> s / fromIntegral (length xs)

k :: Double -> Double
k x = case 1 of z -> z + x

parse :: Read a => String -> a
parse s = case read s of v -> v

newtype W = W Double

unW :: Int -> Double
unW n = case W (fromIntegral n) of W d -> d * 2

main :: IO ()
main = do
  print (half 7, avg [1, 2, 3, 4])
  print (k 2.5)
  print (parse "12" + (1 :: Int))
  print (parse "[1,2,3]" :: [Int])
  print (case read "42" of v -> v + (1 :: Int))
  print (unW 3)
  print (case fromIntegral (3 :: Int) of z@_ -> z * (0.5 :: Double))
