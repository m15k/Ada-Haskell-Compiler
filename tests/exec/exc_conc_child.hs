-- A child task that RAISES fails its Task with the exception VALUE:
-- await rethrows it in the awaiter, and a failed task nobody awaited
-- fails the scope with it at the join - where a catch around the
-- scope receives it (M137). Every child is joined first.
import Control.Concurrent.Scoped

msg :: SomeException -> String
msg e = primExcMessage e

main :: IO ()
main = do
  -- awaited: the awaiter's catch sees the child's value
  scope (\s -> do
    t <- spawn s (putStrLn "child A speaks" >> error "A exploded")
    primCatch (await t >> putStrLn "unreached")
              (\e -> putStrLn ("await caught: " ++ msg e)))
  -- not awaited: the scope's join rethrows it, after joining the
  -- OTHER child, whose output therefore still appears
  primCatch (scope (\s -> do
               spawn s (putStrLn "child B speaks" >> error "B exploded")
               spawn s (yield >> yield >> putStrLn "child C finishes")
               putStrLn "body done"))
            (\e -> putStrLn ("scope caught: " ++ msg e))
  -- a child's IOError crosses the same way, with its fields intact
  primCatch (scope (\s -> spawn s (readFile "/nonexistent/q" >>= putStr) >> return ()))
            (\e -> print (primIoeLocation (primExcIO e), primIoeFilename (primExcIO e)))
  putStrLn "done"
