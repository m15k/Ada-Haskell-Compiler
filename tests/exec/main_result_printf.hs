-- printf at IO () returns a result nobody demands; main must not force
-- it (M142 review: `main = printf "hi\n"` printed and then died).
import Text.Printf

main :: IO ()
main = printf "hi %d\n" (42 :: Int)
