-- Two instance declarations at the SAME byte offsets in different
-- files (M142): desugar and Kinds used to find an instance by its
-- source span, so B's method bodies were attached to A's instance too.
import A
import B

main :: IO ()
main = do
  print T
  print U
