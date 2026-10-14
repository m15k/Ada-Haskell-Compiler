import Control.Exception

t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))

g1 :: Int -> Int
g1 n = (case n of 1 -> 2) + 1

g2 :: Int -> Int
g2 n = let r = case n of
                 1 -> 2   -- c
       in r

g3 :: Int -> [Int]
g3 n = [case n of 1 -> 2, 3]

g4 :: Int -> (Int, Int)
g4 n = (case n of 1 -> 2, 3)

g5 :: Int -> Int
g5 n = case n of
  1 -> x
    where x = 1
  2 | n > 9 -> 3
-- hi

g6 :: Int -> Int
g6 n = f n where f 1 = 1
                 f 2 = 2   {- multi
                 line -}

g7 :: Int -> Int
g7 n = case n of 1 -> 2 ; 3 -> 4

main :: IO ()
main = do
  t (g1 5)
  t (g2 5)
  t (sum (g3 5))
  t (fst (g4 5))
  t (g5 5)
  t (g6 5)
  t (g7 5)
  t (let r = case 5 :: Int of 1 -> 2 in r)
  t (if True then case 5 :: Int of 1 -> 'x' else 'y')
