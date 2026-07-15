module P where
compose f g x = f (g x)
twice f = f . f
apply2 f x = f (f x)
onFst f (a, b) = (f a, b)
sig :: Ord a => [a] -> [a] -> Bool
sig xs ys = xs == ys
