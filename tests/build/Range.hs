-- run_build.sh fixture: a refinement violation. The checked build
-- must die at the range boundary; AHC_UNCHECKED=1 through the shim
-- must strip the claim and print 12.
type Small = Int in 0 .. 9

big :: Small
big = 12

main :: IO ()
main = print big
