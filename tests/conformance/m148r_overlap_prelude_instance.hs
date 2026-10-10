instance {-# OVERLAPPING #-} Show (Either Int Int) where show _ = "EII"
main = print (Left 1 :: Either Int Int)
