-- Embedding the AHC-compiled MathLib from GHC via the generated
-- bindings (AhcLib.hs): two Haskell runtimes in one process,
-- talking through the C ABI. Runtime errors inside the AHC library
-- arrive as IOError.
module Main where

import Control.Exception (try)
import Foreign.C.Types (CLong)

import AhcLib

main :: IO ()
main = do
  ahcLibInit
  sq <- square 12
  putStrLn ("square(12) = " ++ show sq)
  fb <- hs_fib 90
  putStrLn ("fib(90) = " ++ show fb)
  g <- greet "GHC"
  putStrLn g
  st <- sumTo 100
  putStrLn ("sumTo(100) = " ++ show st)
  r <- try (boom 7) :: IO (Either IOError CLong)
  case r of
    Left e  -> putStrLn ("caught: " ++ show e)
    Right v -> putStrLn ("boom(7) = " ++ show v ++ " (unexpected)")
  sq6 <- square 6
  putStrLn ("square(6) = " ++ show sq6)
