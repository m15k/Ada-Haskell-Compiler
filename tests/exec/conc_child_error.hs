-- A dying child fails its Task; a failed Task nobody awaited fails
-- the scope at the join point (Ada's master rule, error edition).
-- The scope body itself completes first - the failure surfaces
-- when the scope joins its children.
import Control.Concurrent.Scoped

main :: IO ()
main = do
  putStrLn "start"
  scope (\s -> do
    spawn s (putStrLn "child speaks" >> error "child exploded")
    putStrLn "body done")
  putStrLn "unreached"
