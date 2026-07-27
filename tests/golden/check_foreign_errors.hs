{-# LANGUAGE ForeignFunctionInterface #-}
foreign import ccall bad1 :: Maybe Int -> Int
foreign import ccall bad2 :: Int -> IO (IO Int)
foreign import ccall bad3 :: Eq a => a -> Int
foreign import ccall bad4 :: a -> Int
foreign import ccall switch :: Int -> Int
foreign import ccall "wrapper" badWrap
  :: (Int -> Int) -> IO (FunPtr (Int -> Bool))
foreign import ccall "dynamic" badDyn
  :: FunPtr (Int -> Int) -> (Int -> Int)

main :: IO ()
main = return ()
