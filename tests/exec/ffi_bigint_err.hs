-- Int silently promotes to bignum past the long range; handing such
-- a value to a foreign import is a clean runtime error, never a
-- truncation.
{-# LANGUAGE ForeignFunctionInterface #-}

foreign import ccall unsafe "labs" c_labs :: Int -> Int

main :: IO ()
main = print (c_labs (2 ^ 70))
