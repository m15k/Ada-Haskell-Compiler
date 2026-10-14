type Name = String
newtype Age = Age Int
data P = P !Name !Age !Bool | Q
f :: P -> Int
f Q = 0
main = let n = "snake_case" in length n `seq` print (f (P n (Age 5) True))
