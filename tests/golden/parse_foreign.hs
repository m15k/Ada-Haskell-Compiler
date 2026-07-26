{-# LANGUAGE ForeignFunctionInterface #-}
foreign import ccall unsafe "labs" c_labs :: Int -> Int
foreign import ccall safe "sin" c_sin :: Double -> Double
foreign import ccall getenv :: String -> IO (Ptr Char)

main :: IO ()
main = return ()
