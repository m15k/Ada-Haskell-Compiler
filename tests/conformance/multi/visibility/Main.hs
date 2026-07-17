import Stack
import Ops (pushAll)

main :: IO ()
main = do
  let s = pushAll [1, 2, 3] empty
  print (size s)
  let (top, s2) = pop s
  print top
  print (size s2)
  print (fst (pop (snd (pop s2))))
  print (fst (pop empty))
