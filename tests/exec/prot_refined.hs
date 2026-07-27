-- Refined state field: the check travels with the field and fires
-- at first observation - no task can ever SEE a violating value.
import Control.Concurrent.Protected

positive :: Int -> Bool
positive n = n > 0

data Gauge = Gauge (Int satisfying positive)

level :: Gauge -> Int
level (Gauge n) = n

adjust :: Int -> Gauge -> (Gauge, ())
adjust d (Gauge n) = (Gauge (n + d), ())

main :: IO ()
main = do
  g <- newProtected (Gauge 10)
  updating g (adjust (-3))
  reading g level >>= print
  updating g (adjust (-7))
  putStrLn "committed unobserved; now look"
  reading g level >>= print
  putStrLn "unreached"
