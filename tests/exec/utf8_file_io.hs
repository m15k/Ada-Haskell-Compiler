-- UTF-8 round trip through the filesystem, plus the FFFD policy on
-- Chars a file can't carry (lone surrogates encode as U+FFFD).
import System.IO

main :: IO ()
main = do
  let s = "h\233llo \955\28450\128077"
  writeFile "utf8_file_io.tmp" s
  r <- readFile "utf8_file_io.tmp"
  print (r == s, length r)
  writeFile "utf8_file_io.tmp" ['a', toEnum 0xD800, 'b']
  r2 <- readFile "utf8_file_io.tmp"
  print (map fromEnum r2)
