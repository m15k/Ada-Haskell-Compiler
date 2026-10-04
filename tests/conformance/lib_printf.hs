-- Text.Printf (M142): every conversion, flag, width and precision
-- form base supports, against GHC 9.4.8. Note GHC's %f/%e/%g with no
-- precision print the SHORTEST digits, not C's six decimals.
import Text.Printf
import Data.Int
import Data.Word

main :: IO ()
main = do
  printf "%d %i %5d|%-5d|%05d %+d % d\n" (42 :: Int) (7 :: Int) (3 :: Int) (3 :: Int) (-3 :: Int) (5 :: Int) (5 :: Int)
  printf "%x %X %o %b %#x %#X %#o %#b\n" (255 :: Int) (255 :: Int) (8 :: Int) (5 :: Int) (255 :: Int) (255 :: Int) (8 :: Int) (5 :: Int)
  printf "%x %u %o\n" (-1 :: Int) (-1 :: Int) (-8 :: Int8)
  printf "%.3d|%8.3d|%-8.3d|%.0d|\n" (5 :: Int) (-5 :: Int) (5 :: Int) (0 :: Int)
  printf "%s|%10s|%-10s|%.2s|%010s\n" "abc" "right" "left" "truncate" "zeros"
  printf "%c%c %% %5c|%-3c|\n" 'o' 'k' 'r' 'l'
  printf "%f %.2f %8.3f %-8.1f|%08.2f %+.1f\n" (3.14159 :: Double) (2.5 :: Double) (1.0 :: Double) (9.99 :: Double) (-2.5 :: Double) (2.25 :: Double)
  printf "%e %.3E %g %G %g %#.0f\n" (1234.5 :: Double) (0.000123 :: Double) (0.0001 :: Double) (1.0e7 :: Double) (123456.0 :: Double) (3 :: Double)
  printf "%f %.3f %e\n" (0.1 :: Float) (2.5 :: Float) (1.0e-3 :: Float)
  printf "%v %v %v %v\n" (1 :: Int) 'c' "str" (2.5 :: Double)
  printf "%*d|%-*d|%*d|%.*f\n" (6 :: Int) (1 :: Int) (4 :: Int) (2 :: Int) (-4 :: Int) (3 :: Int) (3 :: Int) (3.14159 :: Double)
  let s = printf "%d-%s" (1 :: Int) "x" :: String
  putStrLn s
  printf "%d %d %x\n" (123456789012345678901234567890 :: Integer) (-1 :: Integer) (2 ^ 70 :: Integer)
  printf "%d %u %d\n" (maxBound :: Word64) (200 :: Word8) (minBound :: Int64)
  printf "%ld %hd %lld\n" (1 :: Int) (2 :: Int) (3 :: Int)
  printf "%5.1f%%\n" (99.5 :: Double)
  printf "no arguments at all\n"
