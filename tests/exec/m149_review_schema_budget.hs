data T = C0 T T T | C1 T T T | C2 T T T | C3 T T T | C4 T T T | C5 T T T | C6 T T T | C7 T T T | C8 T T T | C9 T T T | C10 T T T | C11 T T T | C12 T T T | C13 T T T | C14 T T T | C15 T T T | C16 T T T | C17 T T T | C18 T T T | C19 T T T | C20 T T T | C21 T T T | C22 T T T | C23 T T T | C24 T T T | C25 T T T | C26 T T T | C27 T T T | C28 T T T | C29 T T T | Leaf
f0 :: T -> Int
f0 Leaf = 0
f1 :: T -> Int
f1 Leaf = 1
f2 :: T -> Int
f2 Leaf = 2
f3 :: T -> Int
f3 Leaf = 3
f4 :: T -> Int
f4 Leaf = 4
main = print (f0 Leaf + f1 Leaf + f2 Leaf + f3 Leaf + f4 Leaf)
