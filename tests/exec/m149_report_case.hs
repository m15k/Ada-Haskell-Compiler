-- M149: a case with no matching alternative; the scrutinee is fully
-- evaluated, so the report shows it whole.
data Cmd = Go Int | Stop | Turn Char deriving Show

run :: Cmd -> String
run c = case c of
  Go n -> "go " ++ show n
  Stop -> "stop"

main :: IO ()
main = do
  putStrLn (run (Go 3))
  let c = Turn 'L'
  print c
  putStrLn (run c)
