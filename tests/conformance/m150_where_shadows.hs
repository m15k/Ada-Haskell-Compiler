-- M150: a where binding shadows an argument of the same name over the
-- guards and the right-hand side, in equations and case alternatives.

plain :: Int -> Int
plain x = x + 1
  where x = 10

guarded :: Int -> String
guarded n
  | n > 5 = "big " ++ show n
  | otherwise = "small " ++ show n
  where n = 7

-- The where binding may use other arguments, but not the shadowed one
-- (it would refer to itself).
pairUp :: Int -> Int -> (Int, Int)
pairUp a b = (a, b)
  where b = a * 100

inCase :: Maybe Int -> Int
inCase m = case m of
  Just v -> v
    where v = 42
  Nothing -> 0

-- A where function's own parameter shadows the where-bound name's
-- outer argument as before.
nested :: Int -> Int
nested y = go 3
  where go y = y * 2

-- Several equations, each with its own shadowing where.
multi :: Int -> Int
multi 0 = z where z = -1
multi z = z where z = 5

main :: IO ()
main = do
  print (plain 1)
  putStrLn (guarded 1)
  print (pairUp 2 3)
  print (inCase (Just 1), inCase Nothing)
  print (nested 100)
  print (multi 0, multi 9)
