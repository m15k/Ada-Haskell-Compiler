data Color = Red | Green | Blue deriving (Eq, Ord)

isWarm :: Color -> Bool
isWarm c = c /= Blue

type Nat = Int satisfying (\n -> n >= 0)

half :: Nat -> Int
half n = n `div` 2

evenSum :: Int satisfying even -> Int satisfying even -> Int
evenSum a b = a + b

describe :: Color satisfying isWarm -> Int
describe c = if c == Red then 2 else 1

main :: IO ()
main = do
  print (half 10)
  print (evenSum 4 6)
  print (describe Green)
  let unforced = half (-8) in print (const 'k' unforced)
  print (describe Blue)
