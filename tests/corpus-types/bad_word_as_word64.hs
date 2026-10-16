-- Word and Word64 are distinct types in GHC (same width): passing a
-- Word where a Word64 is expected needs fromIntegral. AHC had
-- `type Word = Word64` until M150 and accepted this.
import Data.Word

bump :: Word64 -> Word64
bump x = x + 1

main :: IO ()
main = print (bump (3 :: Word))
