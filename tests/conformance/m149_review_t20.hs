import Control.Exception
t :: a -> IO ()
t x = (evaluate x >> putStrLn "ok") `catch` \e -> print (show (e :: SomeException))
[0x10, z] = [1 :: Int, 2]
'\t' : y = "y"
"x\SOH" ++ [] = "q"
Left (-1.5e0) : q = [Left (2 :: Double)] :: [Either Double ()]
main :: IO ()
main = t z >> t y >> t q
