import Control.Exception
data T = A | B
f :: T -> Int
f A = 0
main = do
  r <- try (evaluate (f B))
  case r of
    Left (PatternMatchFail m) -> throwIO (PatternMatchFail m)
    Right v -> print v
