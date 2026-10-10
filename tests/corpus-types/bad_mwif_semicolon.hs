main :: IO ()
main = print (if { | False -> 1 ; | True -> 2 } :: Int)
