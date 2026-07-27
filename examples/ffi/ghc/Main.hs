-- Embedding the AHC-compiled MathLib from GHC via the generated
-- bindings (AhcLib.hs): two Haskell runtimes in one process,
-- talking through the C ABI.
module Main where

import AhcLib

main :: IO ()
main = do
  ahcLibInit
  putStrLn ("square(12) = " ++ show (square 12))
  putStrLn ("fib(90) = " ++ show (hs_fib 90))
  g <- greet "GHC"
  putStrLn g
  r <- sumTo 100
  putStrLn ("sumTo(100) = " ++ show r)
