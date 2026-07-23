-- Report 5.6.1: "import qualified Prelude" leaves nothing in
-- unqualified scope except builtin syntax - the unit type and
-- constructor, list constructors, tuples - which is grammar and
-- cannot be hidden.
import qualified Prelude

f :: [Prelude.Int] -> Prelude.Int
f (x : _) = x
f [] = 0

swap :: (Prelude.Int, Prelude.Char) -> (Prelude.Char, Prelude.Int)
swap (a, b) = (b, a)

u :: ()
u = ()

main :: Prelude.IO ()
main = Prelude.print (f [4, 5], swap (1, 'c'), u)
