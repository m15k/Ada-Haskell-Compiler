import Control.Exception
data P = Maybe Int :* Maybe Int | Z
t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))
(Just b) :* (Just c) = Z
main :: IO ()
main = do
  t b
  t (let (Just x) : (Just y) : _ = [Nothing :: Maybe Int] in x)
  t (let (Just x) : [Just y] = [Nothing :: Maybe Int] in x)
  t (let ~(Just p) :* (Just r) = Z in p)
