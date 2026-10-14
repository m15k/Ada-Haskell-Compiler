{-# LANGUAGE LambdaCase #-}
import Control.Exception

t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))

data R = R { fa :: Int, fb :: Int } | S { fc :: Int } deriving Show

cs :: Int -> Int -> Int
cs = \cases
  1 2 -> 3
  0 _ -> 4

class D a where
  dm :: a -> Int
  dm x = go x
    where go _ | False = 1

instance D Int where
  dm n = h n
    where
      h 0 = 1

instance D Bool

lam2 :: Int
lam2 = (\x
          (Just y) -> x + y) 1 Nothing

cc :: Int -> Int
cc n = case n of
  0 -> 1
  -- trailing
  1 -> 2 where
-- comment at col 0

main :: IO ()
main = do
  t (cs 5 5)
  t (dm (3 :: Int))
  t (dm True)
  t lam2
  t (cc 7)
  t (fb (R { fa = 1 }))
  t (fa (S 1))
  t ((S 1) { fa = 3 })
  t (case [1,2::Int] of [_] -> 'a'; (_:_:_:_) -> 'b')
  t (let { a :: Int; a | False = 1 } in a)
