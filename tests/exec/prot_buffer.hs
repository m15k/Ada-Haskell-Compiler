-- Bounded buffer: entries with barriers both directions.
import Control.Concurrent.Scoped
import Control.Concurrent.Protected

notFull :: ([Int], Int) -> Bool
notFull (xs, cap) = length xs < cap

notEmpty :: ([Int], Int) -> Bool
notEmpty (xs, _) = not (null xs)

push :: Int -> ([Int], Int) -> (([Int], Int), ())
push x (xs, cap) = ((xs ++ [x], cap), ())

pop :: ([Int], Int) -> (([Int], Int), Int)
pop (x : xs, cap) = ((xs, cap), x)

main :: IO ()
main = do
  b <- newProtected ([], 2)
  scope (\s -> do
    spawn s (mapM_ (\i -> entry b notFull (push i)) [1 .. 6])
    spawn s (mapM_ (\_ -> entry b notEmpty pop >>= print) [1 .. 6 :: Int])
    return ())
  putStrLn "drained"
