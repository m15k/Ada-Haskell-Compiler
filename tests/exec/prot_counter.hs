-- Protected basics: two tasks updating one counter through pure
-- transitions; reading takes an atomic snapshot. The total is
-- schedule-independent (differential against GHC via the STM
-- shim).
import Control.Concurrent.Scoped
import Control.Concurrent.Protected

main :: IO ()
main = do
  p <- newProtected (0 :: Int)
  scope (\s -> do
    spawn s (mapM_ (\i -> updating p (\n -> (n + i, ()))) [1 .. 5])
    spawn s (mapM_ (\i -> updating p (\n -> (n + i, ()))) [10, 20, 30])
    return ())
  total <- reading p id
  print total
