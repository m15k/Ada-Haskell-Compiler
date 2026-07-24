-- A provably-false precondition: compile-time warning, check kept.
{-# PRE broken \x -> 2 + 2 == 5 #-}
broken :: Int -> Int
broken x = x

main :: IO ()
main = print (broken 1)
