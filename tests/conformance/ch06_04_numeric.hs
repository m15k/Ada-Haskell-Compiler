-- Report 6.4.2: Integral division - div/mod floor toward negative
-- infinity, quot/rem truncate toward zero.
main :: IO ()
main = do
  print (div 7 2, mod 7 2, quot 7 2, rem 7 2)
  print (div (-7) 2, mod (-7) 2)
  print (quot (-7) 2, rem (-7) 2)
  print (div 7 (-2), mod 7 (-2))
  print (even 4, odd 4)
  print (subtract 3 10)
  print (3 * (-4) + abs (-2))
