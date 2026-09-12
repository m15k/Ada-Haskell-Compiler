-- Report 11.4 / Appendix D: derived Read is the exact inverse of
-- derived Show, at every constructor shape and every precedence.
module Main where

data Colour = Red | Green | Blue deriving (Show, Read, Eq, Enum, Bounded)
data Pair = Pair Int Bool deriving (Show, Read, Eq)
data Rec = Rec { name :: String, age :: Int, tags :: [String] }
  deriving (Show, Read, Eq)
data T a = Leaf | Node (T a) a (T a) deriving (Show, Read, Eq)
data P a b = a :* b deriving (Show, Read, Eq)
data Mixed = M Int (Maybe [Int]) (Either Bool Char) Char String
  deriving (Show, Read, Eq)
data Neg = Neg Int Double deriving (Show, Read, Eq)

tree :: T Int
tree = Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf)

rec1 :: Rec
rec1 = Rec { name = "ann o'hara", age = 30, tags = ["a", "b c"] }

mixed :: Mixed
mixed = M 2 (Just [1, 2]) (Left True) '\n' "x\ty"

roundTrip :: (Show a, Read a, Eq a) => a -> Bool
roundTrip x = read (show x) == x

main :: IO ()
main = do
  -- Enumerations keep their old path.
  print (read "Green" :: Colour, map roundTrip [Red, Green, Blue])
  -- Prefix constructors, at top level and nested under precedence.
  print (read "Pair 1 True" :: Pair, roundTrip (Pair (-3) False))
  print (read "  Pair   7   False  " :: Pair)
  -- Records, including a String field and a list of Strings.
  print (read "Rec {name = \"bo\", age = 4, tags = []}" :: Rec)
  print (roundTrip rec1)
  -- Recursive parameterised types: nesting drives the precedence.
  print (read "Node Leaf 5 Leaf" :: T Int, roundTrip tree)
  print (show tree == show (read (show tree) :: T Int))
  -- Infix constructors read at precedence 9, fields at 10.
  print (roundTrip ((1 :: Int) :* True), read "(1 :* False)" :: P Int Bool)
  -- Fields whose types are themselves Read instances.
  print (roundTrip mixed)
  print (read "M 0 Nothing (Right 'x') 'q' \"\"" :: Mixed)
  -- Negative numbers arrive parenthesised from showsPrec 11.
  print (roundTrip (Neg (-1) (-2.5)), show (Neg (-1) (-2.5)))
  -- Optional parentheses, and the remainder ReadS leaves behind.
  print (read "(Red)" :: Colour, read "((Pair 1 True))" :: Pair)
  print (reads "Leaf rest" :: [(T Int, String)])
  print (reads "Pair 1 True and more" :: [(Pair, String)])
  -- A parse that cannot succeed yields no results, not an error.
  print (reads "Pair 1" :: [(Pair, String)])
  print (reads "Nope" :: [(Colour, String)])
