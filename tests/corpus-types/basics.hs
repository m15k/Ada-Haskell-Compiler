compose f g x = f (g x)
twice f = f . f
len [] = 0
len (_ : xs) = 1 + len xs
sumTo n = if n == 0 then 0 else n + sumTo (n - 1)
isEven n = n `mod` 2 == 0
pairUp x y = (x, y)
names = map fst [(1, "a"), (2, "b")]
total = sumTo 10
main = print total
