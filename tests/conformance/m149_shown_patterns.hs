{-# LANGUAGE MultiWayIf #-}
-- M149: pattern-match failures, caught and shown - GHC 9.4.8's
-- PatternMatchFail texts and source spans, byte for byte.
import Control.Exception

data Shape = Circle Double | Square Double | Triangle Double Double
data R = R { rx :: Int, ry :: Int } | Q { rx :: Int }

area :: Shape -> Double
area (Circle r) = r * r
area (Square s) = s * s

sign :: Int -> String
sign n
  | n > 0 = "pos"
  | n < 0 = "neg"

t :: String -> IO () -> IO ()
t name act = do
  r <- try act
  case r of
    Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
    Right () -> putStrLn (name ++ " ok")

main :: IO ()
main = do
  t "function" (evaluate (area (Triangle 3 4)) >> return ())
  t "guards" (evaluate (length (sign 0)) >> return ())
  t "case" (evaluate (case Just (1 :: Int) of { Nothing -> 0 :: Int }) >> return ())
  t "lambda" (evaluate ((\(Just x) -> x) (Nothing :: Maybe Int)) >> return ())
  t "let" (evaluate (let Just y = (Nothing :: Maybe Int) in y) >> return ())
  t "lazy" (evaluate ((\ ~(Just z) -> z) (Nothing :: Maybe Int)) >> return ())
  t "multi-way if" (evaluate (if | False -> 1 :: Int) >> return ())
  t "missing field" (evaluate (ry (R { rx = 1 })) >> return ())
  t "update" (evaluate (ry ((Q 1) { ry = 2 })) >> return ())
  t "selector" (evaluate (ry (Q 1)) >> return ())
  r <- try (evaluate (area (Square 1 `seq` Triangle 1 1)))
  case r of
    Left (PatternMatchFail m) -> putStrLn ("by type => " ++ m)
    Right v -> print v
