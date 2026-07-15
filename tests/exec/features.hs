data Shape = Circle Int | Rect Int Int deriving (Eq, Show)

area (Circle r) = 3 * r * r
area (Rect w h) = w * h

fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

sumList = foldr (\x acc -> x + acc) 0

class Describable a where
  describe :: a -> String
  describe _ = "something"
  name :: a -> String

instance Describable Shape where
  name (Circle _) = "circle"
  name (Rect _ _) = "rectangle"

main = do
  putStrLn "-- arithmetic & recursion"
  print (fib 20)
  putStrLn "-- lists, laziness (take from infinite would need take; use enumFromTo)"
  print (sumList [1 .. 100])
  print (map (* 2) [1, 2, 3])
  putStrLn "-- ADTs, classes, deriving"
  print (area (Rect 3 4))
  print (Circle 5 == Circle 5)
  print (Rect 1 2 == Circle 3)
  putStrLn (name (Circle 1))
  putStrLn (describe (Rect 1 1))
  putStrLn "-- guards & where"
  putStrLn (classify 42)
  where
    classify n
      | n < 0 = "negative"
      | n == 0 = "zero"
      | otherwise = "positive"
