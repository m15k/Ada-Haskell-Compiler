module Main where
import qualified L
import qualified R
main :: IO ()
main = do
  let a = L.P { L.px = 1, L.py = 2 }
      b = R.P { R.px = True }
  print (L.px a, R.px b)
  print (a { L.px = 10 })
  print (b { R.px = False })
  case a of L.P { L.py = v } -> print v
