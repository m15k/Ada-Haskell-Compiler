-- M149: what a program sees of each runtime failure when it catches the
-- exception and shows it - byte-identical to GHC 9.4.8, call stacks
-- included. One failure per line, so every column is distinct.
import Control.Exception
import Data.Maybe (fromJust)
import Data.Char (chr)

t :: String -> IO () -> IO ()
t name act = do
  r <- try act
  case r of
    Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
    Right () -> putStrLn (name ++ " ok")

forceI :: Int -> IO ()
forceI x = evaluate x >> return ()

main :: IO ()
main = do
  t "error" (forceI (error "boom"))
  t "errorWithoutStackTrace" (forceI (errorWithoutStackTrace "plain"))
  t "undefined" (forceI undefined)
  t "head" (forceI (head []))
  t "tail" (forceI (length (tail ([] :: [Int]))))
  t "init" (forceI (length (init ([] :: [Int]))))
  t "last" (forceI (last []))
  t "index large" (forceI ([1, 2, 3] !! 5))
  t "index negative" (forceI ([1] !! (-1)))
  t "maximum" (forceI (maximum []))
  t "minimum" (forceI (minimum []))
  t "foldr1" (forceI (foldr1 (+) []))
  t "foldl1" (forceI (foldl1 (+) []))
  t "cycle" (forceI (length (take 1 (cycle ([] :: [Int])))))
  t "fromJust" (forceI (fromJust Nothing))
  t "read" (forceI (read "x"))
  t "toEnum" (evaluate (toEnum 5 :: Bool) >> return ())
  t "chr" (evaluate (chr 99999999) >> return ())
  t "succ" (forceI (succ maxBound))
  t "div" (forceI (1 `div` 0))
  t "mod" (forceI (1 `mod` 0))
  t "quot" (forceI (1 `quot` 0))
  t "rem" (forceI (1 `rem` 0))
  t "divMod" (forceI (fst (1 `divMod` 0)))
  t "quotRem" (forceI (fst (1 `quotRem` 0)))
  t "overflow" (forceI (minBound `div` (-1)))
