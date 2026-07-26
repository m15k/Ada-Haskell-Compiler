{-# LANGUAGE ForeignFunctionInterface #-}
foreign import ccall bad1 :: Maybe Int -> Int
foreign import ccall bad2 :: Int -> IO (IO Int)
foreign import ccall bad3 :: Eq a => a -> Int
foreign import ccall bad4 :: a -> Int

main :: IO ()
main = return ()
