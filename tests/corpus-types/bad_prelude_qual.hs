-- hiding filters the QUALIFIED view of the same import too.
import Prelude hiding (map)

main :: IO ()
main = print (Prelude.map (+ 1) [1, 2, 3])
