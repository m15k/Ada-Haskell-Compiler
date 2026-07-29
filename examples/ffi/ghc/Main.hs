-- Embedding the AHC Engine from GHC: two Haskell runtimes in one
-- process, calling each other through the C ABI. GHC calls the AHC
-- exports, and the AHC library calls back into GHC's own
-- foreign-exported host_log.
{-# LANGUAGE ForeignFunctionInterface #-}
module Main where

import Control.Exception (try)
import Foreign.C.String (CString, peekCString)
import Foreign.C.Types (CLong)

import AhcLib

-- The symbol Engine.hs imports - exported from GHC back to C.
foreign export ccall "host_log" hostLog :: CString -> IO ()

hostLog :: CString -> IO ()
hostLog p = do
  s <- peekCString p
  putStrLn ("  [ghc] " ++ s)

text :: String
text = "the quick brown fox jumps over the lazy dog\n\
       \the dog barks and the fox runs\n"

main :: IO ()
main = do
  ahcLibInit

  p <- primes 12
  putStrLn ("primes(12)   = " ++ p)
  f <- factorial 30
  putStrLn ("factorial(30)= " ++ f)
  v <- evalExpr "2 * (3 + 4) - 10 / 2"
  putStrLn ("evalExpr     = " ++ show v)
  w <- wordFreq text
  putStrLn ("wordFreq     = " ++ w)

  putStrLn "analyze:"
  n <- analyze text
  putStrLn ("  -> " ++ show n ++ " words")

  -- A parse failure arrives as IOError, not a dead process.
  r <- try (evalExpr "2 +") :: IO (Either IOError CLong)
  case r of
    Left e -> putStrLn ("evalExpr(bad): " ++ show e)
    Right x -> putStrLn ("evalExpr(bad) = " ++ show x ++ " (unexpected)")

  alive <- evalExpr "6*7"
  putStrLn ("still alive  = " ++ show alive)
