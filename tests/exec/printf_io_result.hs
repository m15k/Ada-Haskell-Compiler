-- base's instance is (a ~ ()) => PrintfType (IO a); Haskell 2010
-- cannot state it, so the IO action's result here is a value nothing
-- may force - and main's result is never forced, as in GHC. The M142
-- review found `main = printf "hi\n"` dying after printing.
import Text.Printf

main :: IO ()
main = printf "hi\n"
