module A where
{-# PRE step \x -> x > 0 #-}
step :: Int -> Int
step x = x + 1
