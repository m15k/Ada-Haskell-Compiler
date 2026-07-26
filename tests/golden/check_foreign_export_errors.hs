{-# LANGUAGE ForeignFunctionInterface #-}
foreign export ccall missing :: Int -> Int

main :: IO ()
main = return ()
