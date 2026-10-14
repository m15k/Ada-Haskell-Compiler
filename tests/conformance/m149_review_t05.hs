import Control.Exception

t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))

data R = R { fa :: Int, fb :: Int } | Q deriving Show

(Just c1) = Nothing :: Maybe Int
Just   c2 = Nothing :: Maybe Int
(x3, Just y3) = (1 :: Int, Nothing :: Maybe Int)
x4 : xs4 = [] :: [Int]
[ a5 , b5 ] = [1 :: Int]
R { fa = f6 } = Q
(Just {- c -} c7) = Nothing :: Maybe Int
(Just
   c8) = Nothing :: Maybe Int
Left (-1) = Left (2 :: Int) :: Either Int ()
'x' : s10 = "y"
"ab\t" ++ s11 = "q"

main :: IO ()
main = do
  t c1
  t c2
  t y3
  t x4
  t a5
  t f6
  t c7
  t c8
  t s10
  let ~(Just (Left q)) = Just (Right 'c') :: Maybe (Either Int Char)
  t q
  let (u, v) : _ = [] :: [(Int,Int)]
  t u
