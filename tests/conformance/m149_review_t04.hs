{-# LANGUAGE MultiWayIf, LambdaCase, EmptyCase #-}
import Control.Exception

t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))

data V
(a, b) = undefined :: (Int, Int)
Just c = Nothing :: Maybe Int
[d1, d2] = [1, 2, 3 :: Int]

wb :: Int -> Int
wb n = p + q
  where (p, Just q) = (n, Nothing)

lz :: Maybe Int -> Int
lz ~(Just z) = z + 1

asp :: [Int] -> Int
asp all@(x:_:[]) = x + length all

lam :: Maybe Int -> Either Int Int -> Int
lam = \(Just a) (Left b) -> a + b

mw :: Int -> Int
mw x
  | x > 0 = if | x > 5 -> 1
               | x < 3 -> 2
  | otherwise = 0

ec :: V -> Int
ec v = case v of {}

lc :: Maybe Int -> Int
lc = \case
  Just 1 -> 1
  Nothing -> 0

sl :: String -> Int
sl "abc" = 1
sl ('x':_) = 2

nl :: Double -> Int
nl 1.5 = 1
nl 2 = 2

un :: Int -> Int
un = undefined

lt :: Int -> Int
lt n = let Just k = lookup n [(1,2)] in k

main :: IO ()
main = do
  t a
  t c
  t d1
  t (wb 1)
  t (lz Nothing)
  t (asp [1])
  t (lam (Just 1) (Right 2))
  t (lam Nothing (Left 2))
  t (mw 4)
  t (ec undefined)
  t (lc (Just 3))
  t (sl "q")
  t (nl 3)
  t (un 3)
  t (lt 5)
  t (errorWithoutStackTrace "ews" :: Int)
  t (error "" :: Int)
  t (error "é\n" :: Int)
  t (let x = x + 1 :: Int in if True then undefined else x)
