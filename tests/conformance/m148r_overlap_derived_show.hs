instance {-# OVERLAPPING #-} Show [Bool] where show _ = "BOOLS"
data R = R [Bool] deriving Show
main = do print [True]; print (R [False]); print (Just [True]); putStrLn (show [[True]])
