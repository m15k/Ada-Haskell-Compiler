-- A type error in an imported module must be rendered against THAT
-- module's file, even when it is only judged after a later module's
-- groups and instances (M142 review: a lib/ module's missing context
-- was reported at lib/Control/Exception.hs:28).
import Bad

data X = X

instance Show X where
  show X = "X"

main :: IO ()
main = putStrLn (render X)
