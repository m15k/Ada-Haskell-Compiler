-- Debug.Trace, the M142 review round: the whole message is forced
-- before anything is written (a nested trace prints first; a raise
-- inside the message writes nothing), NUL characters are dropped with
-- GHC's warning line, and traceIO is an action - printed each time it
-- RUNS, never when merely evaluated. Every stdout write is flushed, so
-- the 2>&1 capture shows evaluation order.
import Debug.Trace
import System.IO
import Control.Exception

say :: String -> IO ()
say s = putStrLn s >> hFlush stdout

main :: IO ()
main = do
  let x = trace ("outer=" ++ show (trace "inner" (1 :: Int))) (2 :: Int)
  say (show x)
  let y = trace "a\0b\0" (3 :: Int)
  say (show y)
  r <- try (evaluate (trace ("partial" ++ error "boom") (4 :: Int)))
  say (either (\e -> "caught: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) show r)
  let t = traceIO "tio"
  t >> t >> t
  let u = traceIO "never-run"
  u `seq` say "evaluated, not run"
  traceIO "tio\0nul"
  mapM_ (\_ -> traceM "tm") [1, 2, 3 :: Int]
  say (show (traceM "in Maybe" :: Maybe ()))
  traceIO ""
  say (trace "unicode \233\8364" "done")
