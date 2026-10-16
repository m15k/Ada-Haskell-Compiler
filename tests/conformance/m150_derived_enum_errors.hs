-- M150 D3: a derived Enum's succ/pred/toEnum errors carry GHC's call
-- stack at the deriving clause's class name.
import Control.Exception

data Colour = Red | Green | Blue
  deriving (Show, Eq, Enum, Bounded)

data Dir = North | South deriving (Show, Enum)

t :: String -> a -> IO ()
t name v = do
  r <- try (evaluate v)
  case r of
    Left e -> putStrLn (name ++ " => " ++ show (e :: SomeException))
    Right _ -> putStrLn (name ++ " => no error")

main :: IO ()
main = do
  t "succ Blue" (succ Blue)
  t "pred Red" (pred Red)
  t "toEnum 7" (toEnum 7 :: Colour)
  t "toEnum (-1)" (toEnum (-1) :: Dir)
  t "succ South" (succ South)
  print [Red ..]
  print (map fromEnum [North, South])
