module Main where
import Left
main :: IO ()
main = case Just 'x' of
  Just c -> putStrLn [c]
  Nothing -> putStrLn "none"
