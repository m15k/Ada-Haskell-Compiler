data K f = K (f Int) deriving (Eq, Show)
main = print (K (Just 1) == K (Just 1), K [3])
