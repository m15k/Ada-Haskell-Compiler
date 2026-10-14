import qualified Data.Text as T
data P = P !T.Text | Q
f :: P -> Int
f Q = 0
main = print (f (P (T.pack "hi")))
