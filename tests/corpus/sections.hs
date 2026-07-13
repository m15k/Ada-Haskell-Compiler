module S where
a = map (2 *) [1 .. 10]
b = filter (> 0) [-1, 0, 1]
c = foldr (:) [] "abc"
d = (`div` 2) 10
e = (subtract 1) 5
f = ((,) 1 2, (,,) 1 2 3)
