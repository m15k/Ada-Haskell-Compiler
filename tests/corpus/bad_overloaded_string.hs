-- Both compilers must reject: IsString [Bool] does not exist (AHC
-- pins the list instance's element to Char; GHC has IsString [Char]
-- only). Guards the soundness of AHC's TyCon-keyed instance pin.
{-# LANGUAGE OverloadedStrings #-}
f :: [Bool] -> Int
f = length

main :: IO ()
main = print (f "abc")
