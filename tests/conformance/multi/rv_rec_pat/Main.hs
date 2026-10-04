data R = R { length :: Int } deriving Show
f (R { length = n }) = n
main = print (f (R 3))
