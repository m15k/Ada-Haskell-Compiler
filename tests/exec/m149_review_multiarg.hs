data T = A | B
f :: T -> T -> Int
f A A = 0
main = let a = B in a `seq` print (f a a)
