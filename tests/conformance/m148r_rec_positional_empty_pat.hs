data E = E Int deriving Show
f E{} = 1
main = print (f (E 3))
