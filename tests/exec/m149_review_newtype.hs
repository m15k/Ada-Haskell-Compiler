newtype W = W (Maybe Int)
g :: W -> Int
g (W (Just x)) = x
main = print (g (W Nothing))
