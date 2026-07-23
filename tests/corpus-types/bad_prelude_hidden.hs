-- A name hidden from the explicit Prelude import is out of scope.
import Prelude hiding (map)

main :: IO ()
main = print (map (+ 1) [1, 2, 3])
