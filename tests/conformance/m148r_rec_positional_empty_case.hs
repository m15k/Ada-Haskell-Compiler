data E = E Int Int | G deriving Show
f :: E -> Int
f x = case x of E{} -> 1; _ -> 2
main = print (f (E 3 4), f G)
