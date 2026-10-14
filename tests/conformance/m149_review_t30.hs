import Control.Exception
fromJust :: Maybe a -> a
fromJust (Just x) = x
head_at_ :: Int
head_at_ = 3
error_at_ :: Int
error_at_ = 4
t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))
main :: IO ()
main = do
  t (fromJust (Nothing :: Maybe Int))
  print (head_at_ + error_at_)
  t (head ([] :: [Int]))
