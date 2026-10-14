import Control.Exception
main :: IO ()
main = do
  r <- try (evaluate (error "boom" + 1 :: Int))
  case r of
    Left e -> putStrLn "caught" >> throwIO (e :: ErrorCall)
    Right v -> print v
