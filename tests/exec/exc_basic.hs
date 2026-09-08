-- The exception machinery below the library (M137): primCatch,
-- primThrow/primThrowIO, primEvaluate, the accessors, and the
-- rethrow rule - a thunk abandoned by a raise re-raises on its next
-- force instead of reporting <<loop>>.
main :: IO ()
main = do
  -- catch an `error`, read it back through the accessors
  primCatch (primEvaluate (error "boom" :: Int) >> putStrLn "unreached")
            (\e -> putStrLn ("caught kind " ++ show (primExcKind e)
                             ++ ": " ++ primExcMessage e))
  -- nested + rethrow: the inner handler sees it first, rethrows the
  -- same value, the outer handler sees that value
  primCatch (primCatch (primThrowIO (primExcErrorCall "inner"))
                       (\e -> do putStrLn ("inner: " ++ primExcMessage e)
                                 primThrowIO e))
            (\e -> putStrLn ("outer: " ++ primExcMessage e))
  -- throw from pure code, raised when the value is demanded
  primCatch (primEvaluate (primThrow (primExcArith 3) + (1 :: Int))
             >> return ())
            (\e -> putStrLn ("arith code " ++ show (primExcCode e)))
  -- laziness: a raise inside a value nobody forces is not a raise
  x <- primCatch (return (error "lazy" :: Int)) (\_ -> return 0)
  r <- primCatch (primEvaluate x >> return "forced fine")
                 (\e -> return ("escaped, then caught: " ++ primExcMessage e))
  putStrLn r
  -- the rethrow rule: a shared thunk forced twice raises twice
  let shared = error "shared" :: Int
  primCatch (primEvaluate shared >> return ())
            (\e -> putStrLn ("first: " ++ primExcMessage e))
  primCatch (primEvaluate shared >> return ())
            (\e -> putStrLn ("second: " ++ primExcMessage e))
  -- a thunk that was UNDER evaluation when an inner one raised is
  -- abandoned too, and becomes a rethrow as well
  let outer = length (show (error "deep" :: Int)) :: Int
  primCatch (primEvaluate outer >> return ())
            (\e -> putStrLn ("deep 1: " ++ primExcMessage e))
  primCatch (primEvaluate outer >> return ())
            (\e -> putStrLn ("deep 2: " ++ primExcMessage e))
  -- the handler's result is the catch's result
  n <- primCatch (primEvaluate (error "v" :: Int)) (\_ -> return 42)
  print n
  -- an IOException built from Haskell round-trips through a raise
  let ioe = primMkIOError 7 "" "custom failure" Nothing
  primCatch (primThrowIO (primExcFromIO ioe))
            (\e -> do let i = primExcIO e
                      print (primIoeType i, primIoeLocation i,
                             primIoeDescription i, primIoeFilename i))
  -- output produced before a raise is never lost
  primCatch (putStr "partial " >> primThrowIO (primExcErrorCall "x"))
            (\_ -> putStrLn "then handled")
  putStrLn "done"
