import Control.Exception

t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))

v :: Int
v | False = 1

(p, q) | False = (1 :: Int, 2 :: Int)

w :: Int -> Int
w n = k
  where k | n > 5 = 1
          | n < 0 = 2

main :: IO ()
main = do
  t v
  t p
  t (w 3)
  t (let Just z | False = Just (1::Int) in z)
