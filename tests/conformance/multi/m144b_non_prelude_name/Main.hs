module Main where
-- fromMaybe is Data.Maybe's, not the Prelude's: GHC rejects this.
main :: IO ()
main = print (fromMaybe 1 (Just (2 :: Int)))
