-- The result of an action is not forced by >> (or by >>=, or by
-- catch): `return undefined >> act` runs act, as in GHC. Until M137
-- thenIO forced it.
main :: IO ()
main = do
  return (error "never forced" :: Int) >> putStrLn "then ran"
  _ <- return (error "nor this" :: Int)
  putStrLn "bind ran"
