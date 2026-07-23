-- Report 5.6.1: "import Prelude (names)" restricts the Prelude to
-- exactly the listed names. Everything this program touches by name
-- is listed; list/tuple syntax and literals are grammar, not
-- Prelude exports, so they need no import.
import Prelude (IO, Int, print, map, (+))

f :: Int -> Int
f x = x + 1

main :: IO ()
main = print (map f [1, 2, 3])
