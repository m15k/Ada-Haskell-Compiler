module Debug.Trace
  ( trace, traceShow, traceShowId, traceId, traceM, traceShowM
  , traceIO
  ) where

-- Debug.Trace (M142). `trace msg x` writes msg to stderr when the
-- application is forced, then returns x. Ordering against stdout
-- follows evaluation order, exactly as GHC's.

trace :: String -> a -> a
trace msg x = case primTraceStr msg of () -> x

traceId :: String -> String
traceId s = trace s s

traceShow :: Show a => a -> b -> b
traceShow v = trace (show v)

traceShowId :: Show a => a -> a
traceShowId v = trace (show v) v

traceM :: Monad m => String -> m ()
traceM msg = trace msg (return ())

traceShowM :: (Show a, Monad m) => a -> m ()
traceShowM v = traceM (show v)

traceIO :: String -> IO ()
traceIO msg = case primTraceStr msg of () -> return ()
