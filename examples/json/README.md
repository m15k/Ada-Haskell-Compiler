# ajson - the second dogfood program

A JSON parser and pretty-printer written in the Haskell subset AHC
compiles, required (like examples/lisp) to behave byte-identically
whether compiled by AHC or interpreted by GHC - the goldens in
tests/ are GHC's output.

    ajson FILE.json           parse, pretty-print (2-space indent)
    ajson --stats FILE.json   object-key frequency table (Data.Map)
    ajson                     read stdin

What it exercises that the Lisp interpreter predates: the file
API, exact float-literal machinery (numbers are built by
fromRational of the exact decimal ratio - the v1.4 path), the
Burger-Dybvig show digits, records-era derived instances, and
Data.Map. Strings store \uXXXX escapes as real code points and
re-escape anything outside printable ASCII on output, so IO stays
ASCII end to end (the same discipline as the fuzzer; a literal
UTF-8 character in the input WOULD diverge, because GHC decodes
bytes to code points and AHC does not - documented, not hidden).

One contract rides along as a showcase: render's indentation
precondition, discharged or checked like any other.
