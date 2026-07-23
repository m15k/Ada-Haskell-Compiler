import Data.List (sort)

lcg :: Int -> Int
lcg x = (x * 1103515245 + 12345) `mod` 2147483648

randoms :: Int -> Int -> [Int]
randoms 0 _ = []
randoms n x = x : randoms (n - 1) (lcg x)

main :: IO ()
main = print (sum (sort (randoms 30000 42)))
