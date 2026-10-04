data R = R { length :: Int } deriving Show
main = print ((R 3) { length = 4 })
