import Control.Exception
data T = A | B
f :: T -> Int
f A = 0
main = do
  r <- try (evaluate (f B))
  case r of
    Left e -> throwIO (e :: PatternMatchFail)
    Right v -> print v
