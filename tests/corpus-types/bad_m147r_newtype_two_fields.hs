newtype T = T Int Int
f :: T -> Int
f (T a b) = a + b
main :: IO ()
main = print (f (T 1 2))
