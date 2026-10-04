-- Text.Printf's error texts (M142), exactly base's. An exec test:
-- the messages are what a failing program prints.
import Text.Printf
import Control.Exception
import Data.Int
import Data.Word

try1 :: String -> IO ()
try1 s = do
  r <- try (evaluate (length s))
  case r of
    Left e  -> putStrLn ("caught: " ++ takeWhile (/= '\n') (show (e :: ErrorCall)))
    Right n -> putStrLn ("ok " ++ show n)

-- The M142 review round: base formats a Char through formatIntegral,
-- length modifiers narrow the unsigned view (and are bad formatting
-- chars on strings and floats), `#` adds no prefix to zero, a
-- precision clears the 0 flag, and a `*` argument is formatted as %d.
try2 :: String -> IO ()
try2 s = do
  r <- try (evaluate (length s))
  case r of
    Left e  -> putStrLn ("caught: " ++ takeWhile (/= '\n') (show (e :: ErrorCall)))
    Right _ -> putStrLn ("[" ++ s ++ "]")

main :: IO ()
main = do
  try1 (printf "%q" (1 :: Int))
  try1 (printf "%d %d" (1 :: Int))
  try1 (printf "%d" (1 :: Int) (2 :: Int))
  try1 (printf "%d" "string")
  try1 (printf "%s" (5 :: Int))
  try1 (printf "trailing %" (1 :: Int))
  try1 (printf "%x" (-1 :: Integer))
  -- # of zero: no prefix
  try2 (printf "%#x|%#X|%#o|%#b|%#.0o|%#5x|%#05o" (0::Int) (0::Int) (0::Int) (0::Int) (0::Int) (0::Int) (0::Int))
  try2 (printf "%#x|%#o|%#.3o|%#b" (1::Int) (8::Int) (8::Int) (0::Integer))
  -- precision clears ZeroPad
  try2 (printf "%08.3d|%08.3x|%-08.3d|%08d|%08.0d" (5::Int) (5::Int) (5::Int) (-5::Int) (0::Int))
  try2 (printf "%08.3f|%08.1e" (3.14159::Double) (2.5::Double))
  -- Char through formatIntegral
  try2 (printf "%d|%i|%x|%X|%o|%b|%u|%5d|%-4c|%v" 'a' 'b' 'c' 'd' 'e' 'f' 'g' 'h' 'i' 'j')
  try2 (printf "%.2c" 'a')
  try2 (printf "%hc" 'a')
  try2 (printf "%lc" (65::Int))
  try2 (printf "%c" (-1::Int))
  try2 (printf "%c" (1114112::Integer))
  try2 (printf "%c" (1114111::Integer))
  try2 (printf "%s" 'x')
  try2 (printf "%f" 'x')
  -- length modifiers narrow
  try2 (printf "%hhx|%hx|%lx|%llx|%Lx" (-1::Int) (-1::Int) (-1::Int) (-1::Int) (-1::Int))
  try2 (printf "%hhx|%hx|%lx|%hhu|%hho" (-1::Integer) (-1::Integer) (-1::Integer) (-1::Integer) (-1::Integer))
  try2 (printf "%hhd|%hhx|%hhx" (300::Int) (300::Int) (255::Word8))
  try2 (printf "%hhu|%hu" (-1::Int8) (-2::Int32))
  try2 (printf "%hhx" 'a')
  try2 (printf "%ls" "str")
  try2 (printf "%lf" (1.5::Double))
  try2 (printf "%hs" "str")
  try2 (printf "%Lv" (3::Int))
  -- star arguments
  try2 (printf "%*d|" 'A' (1::Int))
  try2 (printf "%.*f|" '\2' (3.14159::Double))
  try2 (printf "%*d" (2.5::Double) (1::Int))
  try2 (printf "%*d" "x" (1::Int))
  try2 (printf "%.*d" (3::Integer) (1::Int))
  try2 (printf "%*.*d|" (-6::Int) (3::Int) (7::Int))
  try2 (printf "%-*d|" (-6::Int) (7::Int))
  try2 (printf "%0*d|" (-6::Int) (7::Int))
  try2 (printf "%*.2f|" (8::Int) (1.005::Double))
  try2 (printf "%.*s|" (2::Int) "hello")
  try2 (printf "%" )
  try2 (printf "%l" (1::Int))
  try2 (printf "%hh" (1::Int))
  try2 (printf "%5" (1::Int))
  try2 (printf "%.3" (1::Int))
  try2 (printf "%*" (1::Int))
  try2 (printf "%*d" (1::Int))
  try2 (printf "%.*d" (1::Int))
