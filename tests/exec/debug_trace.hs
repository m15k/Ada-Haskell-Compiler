-- Debug.Trace (M142): trace output goes to stderr at the moment the
-- traced value is forced. Every stdout write is flushed, so the 2>&1
-- capture shows evaluation order, identically under GHC.
import Debug.Trace
import System.IO

fact :: Int -> Int
fact n = trace ("fact " ++ show n) (if n <= 1 then 1 else n * fact (n - 1))

say :: String -> IO ()
say s = putStrLn s >> hFlush stdout

main :: IO ()
main = do
  say "start"
  let x = traceShowId (fact 4)
  x `seq` say ("x = " ++ show x)
  traceM "in IO"
  traceShowM [1, 2, 3 :: Int]
  traceIO "traceIO"
  let r = traceId "returned"
  r `seq` say r
  let b = traceShow (42 :: Int) True
  b `seq` say (show b)
