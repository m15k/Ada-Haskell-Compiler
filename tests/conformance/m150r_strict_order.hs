import Control.Exception
sh :: Either ErrorCall Int -> String
sh = either (\e -> takeWhile (/= '\n') (show e)) show
f :: Int -> Int
f n = n where { !a = error "a" :: Int; !b = error "b" :: Int }
main :: IO ()
main = do
  r <- try (evaluate (let { !a = error "a" :: Int; !b = error "b" :: Int; !c = error "c" :: Int } in 1))
  putStrLn (sh r)
  r2 <- try (evaluate (f 1)); putStrLn (sh r2)
  r3 <- try (do { let { !a = error "a" :: Int; !b = error "b" :: Int }; return 1 }); putStrLn (sh r3)
  r4 <- try (evaluate (let { !a = error "a" :: Int; !(Just b) = error "b" :: Maybe Int } in 1))
  putStrLn (sh r4)
  r5 <- try (evaluate (let { !a = error "a" :: Int; c = 1; !b = error "b" :: Int } in 1))
  putStrLn (sh r5)
