-- Integer is unbounded: no Bounded instance (Report 6.3.7). AHC wired
-- one until M142 and failed at run time instead.
main :: IO ()
main = print (minBound :: Integer)
