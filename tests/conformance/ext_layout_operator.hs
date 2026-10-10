-- Report 10.3 parse-error(t) for an operator at a block's column
-- (M148, found by the M147 scout in cnyegun/json-haskell): the block
-- ends and the operator continues the enclosing expression.
import Control.Applicative

digits :: String -> Maybe (String, String)
digits s = do
    let (ds, rest) = span (`elem` "0123456789") s
    if null ds then Nothing else Just (ds, rest)
    <|>
    Just ("", s)

greeting :: String
greeting = hello
    ++ " world"
  where hello = "hello"

count :: Int
count = case Just 3 of
    Just n -> n
    Nothing -> 0
    `max` 1

main :: IO ()
main = do
  print (digits "12ab", digits "ab")
  putStrLn greeting
  print count
  let x = 5 :: Int
  print (negate x)
  print x
