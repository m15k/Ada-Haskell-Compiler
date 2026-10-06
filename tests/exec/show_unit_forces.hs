-- show of () forces its argument, as GHC's (M146 review: AHC printed
-- "()" for a bottom). GHC: "()" then the divide-by-zero report.
main :: IO ()
main = do
  print ()
  print (div 5 (0 :: Int) `seq` ())
