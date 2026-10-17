module Main where
import Control.Exception
main :: IO ()
main = do
  r7 <- try (evaluate ((\ (Just y) -> y) (Nothing :: Maybe Int)))
  case r7 of Left e -> putStrLn (show (e :: SomeException)); Right v -> print v
  r8 <- try (evaluate ((\ (Just ŷ) -> ŷ) (Nothing :: Maybe Int)))
  case r8 of Left e -> putStrLn (show (e :: SomeException)); Right v -> print v
  r9 <- try (evaluate ((\ (Just ŷŷ) -> 1) (Nothing :: Maybe Int)))
  case r9 of Left e -> putStrLn (show (e :: SomeException)); Right v -> print (v::Int)
  putStrLn "end"
