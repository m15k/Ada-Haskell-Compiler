{-# LANGUAGE LambdaCase #-}
f :: Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int
f = \cases
  a b c d e g h i -> a+b+c+d+e+g+h+i
main :: IO ()
main = print (f 1 2 3 4 5 6 7 8)
