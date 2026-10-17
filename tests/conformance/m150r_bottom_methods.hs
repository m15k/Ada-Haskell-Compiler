import Control.Exception
newtype Act = Act (Int -> Int)
instance Eq Act where
  (==) = error "Act: no equality"
instance Ord Act where
  compare = error "Act: no order"
data Cfg = Cfg Int (Maybe Act) deriving (Eq, Ord)
t :: String -> Bool -> IO ()
t n v = do
  r <- try (evaluate v)
  case r of
    Left e -> putStrLn (n ++ " => error: " ++ takeWhile (/= '\n') (show (e :: SomeException)))
    Right b -> putStrLn (n ++ " => " ++ show b)
main = do
  t "list len" ([Act id] == [])
  t "maybe nothing" (Just (Act id) == Nothing)
  t "cfg diff int" (Cfg 1 Nothing == Cfg 2 (Just (Act id)))
  t "cfg nothing" (Cfg 1 Nothing == Cfg 1 Nothing)
  t "list len again" ([Act id] == [])
  t "ord list" ([Act id] < [])
  t "ord pair" ((1::Int, Act id) < (2, Act id))
  t "ord cfg" (Cfg 1 Nothing < Cfg 2 Nothing)
  t "maybe same" (Just (Act id) == Just (Act id))
