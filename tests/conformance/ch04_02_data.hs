-- Report 4.2.1-4.2.3: data, newtype, type synonyms; deriving.
data Shape = Circle Int | Square Int | Free
  deriving (Eq, Ord)

newtype Wrapper = Wrap Int deriving (Eq, Ord)

type Pair = (Int, Int)

perimeterish :: Shape -> Int
perimeterish (Circle r) = 6 * r
perimeterish (Square s) = 4 * s
perimeterish Free       = 0

addPair :: Pair -> Int
addPair (a, b) = a + b

main :: IO ()
main = do
  print (perimeterish (Circle 2), perimeterish (Square 3))
  print (Circle 1 == Circle 1, Circle 1 == Square 1)
  print (compare (Circle 5) (Square 1))
  print (Circle 2 < Circle 3, Square 9 < Free)
  print (Wrap 3 == Wrap 3, Wrap 1 < Wrap 2)
  print (addPair (20, 2))
