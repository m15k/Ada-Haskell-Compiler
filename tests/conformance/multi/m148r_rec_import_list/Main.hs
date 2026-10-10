{-# LANGUAGE RecordWildCards #-}
import A (P(P), mkDefault)
px :: Int
px = 100
f :: P -> Int
f P{..} = px
main :: IO ()
main = print (f mkDefault)
