-- System.Random's IO half (M142): the global generator (a process-
-- global IORef slot, seeded from the clock on first use) and
-- initStdGen are nondeterministic by design, so this prints only
-- properties - its output is the same under GHC (the .out is oracled
-- with runghc) and on every run. The allocation in the loops also
-- drives collections while the slot holds the only reference to the
-- generator, which is what exec-own checks for the new GC root.
import System.Random
import Control.Monad (replicateM)

main :: IO ()
main = do
  rolls <- replicateM 1000 (randomRIO (1, 6 :: Int))
  print (all (\r -> r >= 1 && r <= 6) rolls)
  print (all (`elem` rolls) [1 .. 6])
  g1 <- newStdGen
  g2 <- newStdGen
  print (fst (random g1 :: (Int, StdGen)) /= fst (random g2 :: (Int, StdGen)))
  setStdGen (mkStdGen 7)
  g <- getStdGen
  print (show g == show (mkStdGen 7))
  print (g == mkStdGen 7)
  x <- getStdRandom (randomR (1, 10 :: Int))
  print (x >= 1 && x <= 10)
  -- getStdRandom advanced the global generator exactly as randomR does
  g' <- getStdGen
  print (g' == snd (randomR (1, 10 :: Int) (mkStdGen 7)))
  print (x == fst (randomR (1, 10 :: Int) (mkStdGen 7)))
  i1 <- initStdGen
  i2 <- initStdGen
  print (i1 /= i2)
  ds <- replicateM 2000 (randomIO :: IO Double)
  print (all (\d -> d > 0 && d <= 1) ds)
  -- after setStdGen, randomRIO replays mkStdGen 7's stream
  setStdGen (mkStdGen 7)
  ys <- replicateM 50 (randomRIO (0, 1000 :: Integer))
  print (ys == take 50 (randomRs (0, 1000) (mkStdGen 7)))
  bs <- replicateM 200 (randomIO :: IO Bool)
  print (or bs && not (and bs))
  putStrLn "done"
