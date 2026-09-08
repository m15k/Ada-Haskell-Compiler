-- An exception nobody catches: rendered after "ahc: " on stderr,
-- exit 1, and the output produced before it survives. ErrorCall
-- keeps the historical "error: MSG" text.
main :: IO ()
main = do
  putStrLn "before"
  primThrowIO (primExcErrorCall "nobody caught this")
  putStrLn "unreached"
