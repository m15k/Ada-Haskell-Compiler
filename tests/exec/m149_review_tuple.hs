f :: (Int,Int,Int,Int,Int,Int,Int) -> Int
f (0,_,_,_,_,_,_) = 0
main = let t = (1,2,3,4,5,6,7) in print (f t)
