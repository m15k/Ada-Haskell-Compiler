-- M150 D2: a function field has no Eq (GHC: No instance for
-- (Eq (Int -> Int)) arising from the first field of 'R').
data R = R { g :: Int -> Int } deriving Eq

main :: IO ()
main = print (g (R (+ 1)) 2)
