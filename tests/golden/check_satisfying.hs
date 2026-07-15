data Color = Red | Green | Blue deriving (Eq, Ord)

isWarm :: Color -> Bool
isWarm c = c /= Blue

type Nat = Int satisfying (\n -> n >= 0)

half :: Nat -> Int
half n = n `div` 2

evenOnly :: Int satisfying even -> Int
evenOnly n = n

warmth :: Color satisfying isWarm -> Int
warmth c = if c == Red then 2 else 1

blend :: Nat -> (Int in 0 .. 100) -> Int
blend a b = a + b
