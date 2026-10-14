data P = P !(Int -> Int) | Q
f :: P -> Int
f Q = 0
main = print (f (P (+1)))
