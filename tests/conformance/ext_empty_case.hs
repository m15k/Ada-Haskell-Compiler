{-# LANGUAGE EmptyCase, LambdaCase #-}
-- EmptyCase, always on in AHC (M148): `case v of {}` forces v.
import Control.Exception

data Void

absurd :: Void -> a
absurd v = case v of {}

absurd' :: Void -> a
absurd' = \case {}

main :: IO ()
main = do
  r <- try (evaluate (absurd (error "forced") :: Int))
  putStrLn (either (\e -> "caught: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) show r)
  r2 <- try (evaluate (absurd' (error "forced too") :: Int))
  putStrLn (either (\e -> "caught: " ++ takeWhile (/= '\n') (show (e :: ErrorCall))) show r2)
  print (length [absurd v | v <- ([] :: [Void])])
