-- A raise inside a Protected entry's BODY or BARRIER that another
-- task's epilogue evaluates belongs to the ENTERING task: the updater's
-- own committed transition stands, the waiter's entry rethrows when
-- it resumes, and the state a raising body would have produced is
-- never installed. Found by the M137 adversarial review: the updater's
-- handler caught it and the waiter parked forever.
import Control.Concurrent.Scoped
import Control.Concurrent.Protected

main :: IO ()
main = do
  p <- newProtected (0 :: Int)
  q <- newProtected (0 :: Int)
  scope (\s -> do
    spawn s (primCatch (entry p (> 0) (\n -> (error "state boom", n))
                        >>= \r -> putStrLn ("child A got " ++ show (r :: Int)))
                       (\e -> putStrLn ("child A caught: " ++ primExcMessage e)))
    spawn s (primCatch (entry q (\n -> if n == 0 then False else error "barrier boom")
                                (\n -> (n, n))
                        >>= \r -> putStrLn ("child B got " ++ show (r :: Int)))
                       (\e -> putStrLn ("child B caught: " ++ primExcMessage e)))
    yield
    r1 <- primCatch (updating p (\n -> (n + 1, "parent updated p")))
                    (\e -> return ("parent caught: " ++ primExcMessage e))
    putStrLn r1
    r2 <- primCatch (updating q (\n -> (n + 1, "parent updated q")))
                    (\e -> return ("parent caught: " ++ primExcMessage e))
    putStrLn r2)
  vp <- reading p id
  vq <- reading q id
  putStrLn ("states after: " ++ show (vp, vq))
