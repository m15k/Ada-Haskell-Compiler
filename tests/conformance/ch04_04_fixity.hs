-- Report 4.4.2: fixity declarations for user operators.
infixl 6 <+>
infixr 5 +>
infix  4 ===

(<+>) :: Int -> Int -> Int
a <+> b = a + b * 2

(+>) :: Int -> [Int] -> [Int]
a +> xs = a : xs

(===) :: Int -> Int -> Bool
a === b = a == b

main :: IO ()
main = do
  print (1 <+> 2 <+> 3)
  print (1 +> 2 +> [3])
  print (1 <+> 2 === 5)
  print (2 ^^^ 3)
  where
    (^^^) = \a b -> a * 10 + b
