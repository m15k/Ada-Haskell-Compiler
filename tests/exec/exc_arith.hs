-- Division by zero raises ArithException DivideByZero (index 3) at
-- Int and Integer, for all four operators; a bad chr raises ErrorCall
-- with GHC's text. The last one is left uncaught: its stderr line is
-- the historical "ahc: divide by zero".
report :: SomeException -> IO ()
report e = print (primExcKind e, primExcCode e)

main :: IO ()
main = do
  primCatch (primEvaluate (1 `div` (0 :: Int)) >> return ()) report
  primCatch (primEvaluate (1 `mod` (0 :: Int)) >> return ()) report
  primCatch (primEvaluate (1 `quot` (0 :: Int)) >> return ()) report
  primCatch (primEvaluate (1 `rem` (0 :: Int)) >> return ()) report
  primCatch (primEvaluate ((10 ^ (30 :: Int)) `div` (0 :: Integer)) >> return ()) report
  primCatch (primEvaluate (toEnum 5000000 :: Char) >> return ())
            (\e -> putStrLn (primExcMessage e))
  n <- primCatch (primEvaluate (7 `div` (0 :: Int))) (\_ -> return (-1))
  print n
  print (1 `div` (0 :: Int))
  putStrLn "unreached"
