-- System.Random.SplitMix known answers (M142): AHC's transcription of
-- splitmix-0.1.3.2 against the package itself under GHC.
import System.Random.SplitMix
import Data.Word

seeds :: [Word64]
seeds = [0, 1, 42, fromIntegral (-1 :: Int), maxBound]

stepN :: Int -> SMGen -> SMGen
stepN 0 g = g
stepN n g = stepN (n - 1) (snd (nextWord64 g))

takeGen :: Int -> (SMGen -> (a, SMGen)) -> SMGen -> [a]
takeGen 0 _ _ = []
takeGen n f g = case f g of (x, g') -> x : takeGen (n - 1) f g'

report :: Word64 -> IO ()
report s = do
  let g = mkSMGen s
  putStrLn ("seed " ++ show s ++ ": " ++ show g)
  print (takeGen 20 nextWord64 g)
  let (a, b) = splitSMGen (stepN 3 g)
  print a
  print b
  print (takeGen 20 nextInt g)
  print (takeGen 20 nextDouble g)
  print (takeGen 20 nextWord32 g)
  print (takeGen 10 (nextInteger (-(2 ^ 70)) (3 ^ 50)) g)
  print (takeGen 10 (nextInteger 5 (-7)) g)
  print (takeGen 10 (nextInteger 9 9) g)
  print (takeGen 10 (bitmaskWithRejection64 5) g)
  print (takeGen 10 (bitmaskWithRejection64' 1000) g)
  print (takeGen 10 (bitmaskWithRejection32 7) g)
  print (takeGen 10 (bitmaskWithRejection32' 100000) g)
  print (takeGen 5 (bitmaskWithRejection64' maxBound) g)
  print (unseedSMGen (snd (nextWord64 g)))

main :: IO ()
main = do
  mapM_ report seeds
  print (seedSMGen 2 2, seedSMGen' (7, 8), unseedSMGen (seedSMGen 3 4))
  print (takeGen 3 (\g -> case nextTwoWord32 g of (a, b, g') -> ((a, b), g')) (mkSMGen 1337))
