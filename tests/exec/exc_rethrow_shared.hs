-- A shared thunk whose evaluation raised is a rethrow thunk; forcing
-- it again and again raises the same exception every time WITHOUT
-- growing (the M137 review found each force chained one more
-- indirection: quadratic time, an uncollectable chain). 20000
-- forces here take milliseconds, not seconds; the outputs pin the
-- semantics and the harness's timeout pins the rest.
main :: IO ()
main = do
  let shared = error "shared boom" :: Int
  let go :: Int -> Int -> IO Int
      go 0 acc = return acc
      go k acc = do
        n <- primCatch (primEvaluate shared) (\e -> return (length (primExcMessage e)))
        go (k - 1) (acc + n)
  total <- go 20000 0
  print total
  primCatch (primEvaluate shared >> return ())
            (\e -> putStrLn ("still: " ++ primExcMessage e))
