-- A type synonym whose expansion is a partially applied (->) still
-- denotes a function type once its surplus arguments arrive, so a
-- foreign import written through it is marshallable (M142 review:
-- Kinds built the raw `(->) CInt CInt` spine and said "not
-- marshallable"). tests/exec/contract_arrow_synonym.hs pins the
-- contract half.
import Foreign.C.Types

type P a = (->) a
type Q = (->) CInt

foreign import ccall "abs" c_abs :: P CInt CInt
foreign import ccall "labs" c_labs :: (->) CLong CLong
foreign import ccall "abs" c_abs2 :: Q CInt

twice :: P (P Int Int) (P Int Int)
twice f = f . f

main :: IO ()
main = do
  print (c_abs (-5), c_labs (-7), c_abs2 (-9))
  print (twice (+ 3) 10)
