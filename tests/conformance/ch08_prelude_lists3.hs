-- Prelude: span, break, splitAt, unzip, folds1, words, lines.
main :: IO ()
main = do
  print (span even [2, 4, 5, 6])
  print (break (> 2) [1, 2, 3, 4])
  print (splitAt 2 [1, 2, 3])
  print (splitAt 0 [1], splitAt 9 [1])
  print (unzip [(1, 'a'), (2, 'b')])
  print (foldr1 (-) [10, 3, 2], foldl1 (-) [10, 3, 2])
  print (words "ab cd  ef")
  print (words "  lead trail ")
  print (lines "one\ntwo\n")
  print (lines "no-newline")
