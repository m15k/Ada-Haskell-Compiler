module Main where
import qualified A
import qualified B
main :: IO ()
main = do
  print (A.mk 3)
  print (B.mk 2.5)
  print [A.Circle 1, A.Square 2]
  print [B.Tri, B.Circle 1 2]
  print (A.Circle 1 < A.Square 0, B.Tri < B.Circle 0 0)
  print (compare (B.Circle 1 2) (B.Circle 1 3), A.mk 1 == A.Circle 1)
  print (maximum [B.Tri, B.Circle 9 9], minimum [A.Square 1, A.Circle 5])
