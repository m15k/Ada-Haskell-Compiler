import Control.Exception

t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))

data Op = Int :+ Int | N deriving Show

Left (-1) = Left (2 :: Int) :: Either Int ()
[0x10, _] = [1 :: Int, 2]
w@(Just v) = Nothing :: Maybe Int
('\n', c) = ('a', 'b')
(m :+ 0) = 1 :+ (1 :: Int)
Just (Just (u)) = Just Nothing :: Maybe (Maybe Int)
Just  ( k ) = Nothing :: Maybe Int
[] = [()]
"x\SOH" = "y"
((a, b), Just c2) = ((1 :: Int, 2 :: Int), Nothing :: Maybe Int)
Just 1.50 = Just (2 :: Double)

main :: IO ()
main = do
  t (case Left 2 :: Either Int () of Left (-1) -> 0)
  t v
  t w
  t c
  t m
  t u
  t k
  t a
