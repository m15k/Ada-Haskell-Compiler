-- The foreign-export fixture: built with `ahc-build.sh --lib` and
-- driven by main.c through the generated ahc_exports.h.
{-# LANGUAGE ForeignFunctionInterface #-}
module MathLib where

foreign export ccall square :: Int -> Int
square :: Int -> Int
square x = x * x

foreign export ccall "hs_fib" fib :: Int -> Int
fib :: Int -> Int
fib n = go n 0 1
  where go k a b = if k == 0 then a else go (k - 1) b (a + b)

foreign export ccall greet :: String -> String
greet name = "hello, " ++ name ++ "!"

foreign export ccall sumTo :: Int -> IO Int
sumTo :: Int -> IO Int
sumTo n = return (sum [1 .. n])
