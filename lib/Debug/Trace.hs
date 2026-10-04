module Debug.Trace
  ( trace, traceShow, traceShowId, traceId, traceM, traceShowM
  , traceIO
  ) where

-- Debug.Trace (M142). `trace msg x` writes msg to stderr when the
-- application is forced, then returns x. Ordering against stdout
-- follows evaluation order, exactly as GHC's. The message is forced
-- whole before anything is written (a nested trace prints first, a
-- raise inside the message writes nothing), NUL characters are
-- dropped with GHC's warning line, and each message is one write.

trace :: String -> a -> a
trace msg x = case primTraceStr msg of () -> x

traceId :: String -> String
traceId s = trace s s

traceShow :: Show a => a -> b -> b
traceShow v = trace (show v)

traceShowId :: Show a => a -> a
traceShowId v = trace (show v) v

traceM :: Applicative f => String -> f ()
traceM msg = trace msg (pure ())

traceShowM :: (Show a, Applicative f) => a -> f ()
traceShowM v = traceM (show v)

-- An IO action: the message is written each time it RUNS, never when
-- the action is merely evaluated.
traceIO :: String -> IO ()
traceIO = primTraceIO
