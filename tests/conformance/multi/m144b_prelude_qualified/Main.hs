module Main where
-- Prelude.isJust: the Prelude does not export it, qualified or not.
main :: IO ()
main = print (Prelude.isJust (Just (2 :: Int)))
