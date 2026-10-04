-- A function type against an application whose head is a type
-- constructor other than (->) is an immediate mismatch, reported on
-- the two whole types (M142 review: decomposing the arrow first said
-- "couldn't match type '(->) ?3' with 'Maybe'" and bound metas on the
-- way). GHC rejects all three; tests/corpus-types/bad_arrow_vs_tycon.hs
-- pins the spurious-instance half with metas in play.
k :: Int -> Int
k = negate

x :: Maybe Int
x = k

h :: [Bool]
h = not

e :: Either Bool Char
e = (&&)
