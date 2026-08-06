-- Decoding is total: invalid UTF-8 on stdin becomes U+FFFD, one per
-- rejected sequence, never a crash (AHC policy; GHC throws here).
main :: IO ()
main = do
  s <- getContents
  print (map fromEnum s)
