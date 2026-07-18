import Facade

main :: IO ()
main = do
  print (spin (Widget 1))
  print (twice (Widget 5))
  print (Widget 2 == Widget 2)
