{-# LANGUAGE OverloadedStrings #-}
-- OverloadedStrings: string literals at Text and [Char]. AHC's
-- overloading is unconditional (LANGUAGE pragmas are ignored); the
-- pragma is for GHC, the oracle.
import qualified Data.Text as T

greet :: T.Text
greet = "h\233llo \955"

shout :: String
shout = "still a String"

main :: IO ()
main = do
  print greet
  print (T.length greet, T.length ("\955\28450" :: T.Text))
  print (T.append "ab" "\955c")
  print (T.take 2 ("abcd" :: T.Text), T.drop 1 ("x\955y" :: T.Text))
  putStrLn shout
  print (length ("abc" :: String), null ("" :: String),
         ("a" :: String) == "b")
  print (show "xy")
  print (words "a b c")
