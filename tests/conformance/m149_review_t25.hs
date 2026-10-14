import Control.Exception
main :: IO ()
main = do
  (do { Just x <- return (Nothing :: Maybe Int) ; print x }) `catch` \e -> print (show (e :: SomeException))
  (do
     (a, Left b) <- return (1 :: Int, Right 'c' :: Either Int Char)
     print a) `catch` \e -> print (show (e :: SomeException))
  (do [z] <- return "ab"; print z) `catch` \e -> print (show (e :: SomeException))
  print (do { Just y <- Just Nothing; return (y :: Int) })
  print [w | Just w <- [Nothing, Just 'q']]
