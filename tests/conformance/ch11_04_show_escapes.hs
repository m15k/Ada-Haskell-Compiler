-- Report 11.4 showLitChar: ASCII mnemonics for the control
-- characters and DEL, single-letter escapes where the Report gives
-- one, decimal above DEL, and the \& guards (a digit after a
-- decimal escape, an 'H' after \SO). Plus literal fidelity for
-- surrogate escapes, which UTF-8 cannot represent but the Report
-- still says denote that Char.
newtype W = W String
instance Show W where show (W s) = s

main :: IO ()
main = do
  print '\a' >> print '\b' >> print '\f' >> print '\v'
  print '\DEL' >> print '\SO' >> print '\NUL' >> print '\ESC'
  print "\bx" >> print "\SOH" >> print "\SO\&H" >> print "\955\&5"
  print "a\NULb" >> print (show '\a') >> print (show "\NUL")
  print '"' >> print "'" >> print '\\' >> print "\\"
  print (map fromEnum "\xD800", "\xD800" == ['\xD800'])
  print (length "\xD800\xDFFF", map fromEnum "a\xD800b")
  -- Generic showList over a user Show emitting a RAW NUL: the
  -- rendering must survive it whole. Reported as code points
  -- because the harness compares through a shell capture, which
  -- cannot carry a NUL byte.
  print (map fromEnum (show [[W "\NUL"], [W "rest"]]))
