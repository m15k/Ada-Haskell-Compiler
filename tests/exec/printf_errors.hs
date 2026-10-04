-- Text.Printf's error texts (M142), exactly base's. An exec test:
-- the messages are what a failing program prints.
import Text.Printf
import Control.Exception

try1 :: String -> IO ()
try1 s = do
  r <- try (evaluate (length s))
  case r of
    Left e  -> putStrLn ("caught: " ++ takeWhile (/= '\n') (show (e :: ErrorCall)))
    Right n -> putStrLn ("ok " ++ show n)

main :: IO ()
main = do
  try1 (printf "%q" (1 :: Int))
  try1 (printf "%d %d" (1 :: Int))
  try1 (printf "%d" (1 :: Int) (2 :: Int))
  try1 (printf "%d" "string")
  try1 (printf "%s" (5 :: Int))
  try1 (printf "trailing %" (1 :: Int))
  try1 (printf "%x" (-1 :: Integer))
