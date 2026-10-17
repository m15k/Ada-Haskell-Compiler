module Main where
import Control.Exception
sh :: Either PatternMatchFail Int -> String
sh = either show show
f :: Int -> Int
f !0 = 1
main :: IO ()
main = do
  r <- try (evaluate (let !(Just a) = (Nothing :: Maybe Int) in 1)); putStrLn (sh r)
  r2 <- try (evaluate (let (!a, Just b) = (1 :: Int, Nothing :: Maybe Int) in b)); putStrLn (sh r2)
  r3 <- try (evaluate (f 2)); putStrLn (sh r3)
  r4 <- try (evaluate (case Just 2 of Just !0 -> 1)); putStrLn (sh r4)
  r5 <- try (evaluate (let Just !b = (Nothing :: Maybe Int) in b)); putStrLn (sh r5)
  r6 <- try (evaluate (let !(Just a) = (Nothing :: Maybe Int) in a)); putStrLn (sh r6)
  r7 <- try (evaluate ((\ !(Just a) -> a) (Nothing :: Maybe Int))); putStrLn (sh r7)
  putStrLn "end"
