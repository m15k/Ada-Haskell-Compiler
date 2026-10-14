import Control.Exception

t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))

lz :: Int -> Maybe Int -> Int
lz 0 _ = 0
lz n ~(Just z) =
  z + n

cz :: Maybe Int -> Int
cz m = case m of
  ~(Just z) -> z

lm :: Maybe Int -> Int
lm = \ ~(Just z) -> z

wz :: Int -> Int
wz n = r
  where ~(Just r) = if n > 0 then Nothing else Just 1

nest :: (Int, Maybe Int) -> Int
nest (a, ~(Just b)) = a + b

main :: IO ()
main = do
  t (lz 1 Nothing)
  t (cz Nothing)
  t (lm Nothing)
  t (wz 1)
  t (nest (1, Nothing))
  t (let f ~[x] = x :: Int in f [])
  r <- return Nothing
  let ~(Just w) = r :: Maybe Int
  t w
  ~(Just v) <- return (Nothing :: Maybe Int)
  t v
