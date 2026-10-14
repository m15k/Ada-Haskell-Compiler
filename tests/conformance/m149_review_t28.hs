import Control.Exception
data T = T deriving Show
instance Read T where
  readsPrec _ s = [(T, s), (T, s)]
t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))
main :: IO ()
main = do
  t (read "" :: T)
  t (read "1 2" :: Int)
  t (let r = read in (r "x" :: Int))
