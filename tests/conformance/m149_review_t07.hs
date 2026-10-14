{-# LANGUAGE LambdaCase #-}
import Control.Exception

t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))

(+++) :: [Int] -> [Int] -> [Int]
[] +++ ys = ys

infixl 5 `op`
op :: Int -> Int -> Int
0 `op` y = y
1 `op` y = y + 1

data P = P Int Int
class K a where
  (<+>) :: a -> a -> Int
instance K P where
  P 0 _ <+> P _ 0 = 1

pg :: Maybe Int -> Int
pg m | Just x <- m, x > 0 = x

cg :: Int -> Int
cg n = case n of
  k | k > 10 -> 1
    | k < 0 -> 2

lcm2 :: Int -> Int
lcm2 = \case { 1 -> 1 }

main :: IO ()
main = do
  t ([1] +++ [2])
  t (2 `op` 3)
  t (P 1 1 <+> P 1 1)
  t (pg Nothing)
  t (cg 5)
  t (lcm2 2)
  t (let { go :: Int -> Int; go 0 = 0 } in go 1)
  t ((\x -> case x of { Just y -> y :: Int }) Nothing)
  t (let f = \(a, Just b) -> a + b :: Int in f (1, Nothing))
