-- A thunk abandoned by a raise is a rethrow for EVERY task: task A
-- forces a shared thunk, the raise is caught in A, and task B
-- forcing the same thunk afterwards observes the same exception -
-- never a dead blackhole, never a deadlock report (M137).
import Control.Concurrent.Scoped

main :: IO ()
main = do
  let shared = error "shared boom" + 1 :: Int
  scope (\s -> do
    spawn s (primCatch (primEvaluate shared >> return ())
                       (\e -> putStrLn ("A caught: " ++ primExcMessage e)))
    spawn s (yield >> primCatch (primEvaluate shared >> return ())
                                (\e -> putStrLn ("B caught: " ++ primExcMessage e)))
    return ())
  putStrLn "done"
