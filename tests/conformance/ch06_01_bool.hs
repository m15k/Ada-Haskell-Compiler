-- Report 6.1.1: Bool - (&&), (||), not, otherwise; short-circuit.
main :: IO ()
main = do
  print (True && False, True || False)
  print (not True)
  print otherwise
  print (False && error "not evaluated")
  print (True || error "not evaluated")
  print (1 < 2, 2 <= 2, 3 > 4, 4 >= 5, 1 == 1, 1 /= 1)
