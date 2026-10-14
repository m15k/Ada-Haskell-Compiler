data N = N N | L Int
f :: N -> Int
f (N (N (N (N (L 0))))) = 0
main = print (f (N (N (N (N (N (N (L 1))))))))
