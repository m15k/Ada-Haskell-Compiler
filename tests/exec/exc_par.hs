-- A raise inside a spark: the value surfaces when the program
-- demands the sparked thunk, on the demanding task, where a catch
-- receives it - and demanding it again raises again (M137).
import Control.Parallel

main :: IO ()
main = do
  let bad = error "sparked boom" :: Int
      good = sum [1 .. 100 :: Int]
      both = bad `par` (good `pseq` good + bad)
  primCatch (primEvaluate both >> return ())
            (\e -> putStrLn ("caught: " ++ primExcMessage e))
  primCatch (primEvaluate both >> return ())
            (\e -> putStrLn ("again: " ++ primExcMessage e))
  print good
