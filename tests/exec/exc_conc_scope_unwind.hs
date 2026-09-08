-- The scope BODY raises while a child still runs: the exception
-- waits for the child (Ada's master rule), the scope is retired, and
-- only then does the handler run. The first exception wins - a
-- child raising during that join is lost, as in Ada.
import Control.Concurrent.Scoped

main :: IO ()
main = do
  primCatch (scope (\s -> do
               spawn s (yield >> putStrLn "child still ran" >> yield >> putStrLn "child finished")
               spawn s (yield >> yield >> yield >> error "child raised during the join")
               putStrLn "body raises"
               primThrowIO (primExcErrorCall "from the body")
               putStrLn "unreached"))
            (\e -> putStrLn ("handler: " ++ primExcMessage e))
  putStrLn "done"
