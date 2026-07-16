type Clock = Int mod 12
type Byte = Int mod 256

shift :: Clock -> Int -> Clock
shift t d = t + d

sumBytes :: Byte -> Byte -> Byte
sumBytes a b = a + b

modmap :: (m mod -> m mod) -> m mod -> m mod
modmap f x = f x
