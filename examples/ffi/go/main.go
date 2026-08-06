// Embedding the AHC Engine from Go through the generated cgo
// package. Both directions: Go calls the Haskell exports (every call
// returns (T, error)), and the Haskell library calls back out to the
// host_log exported below.
package main

import "C"

import (
	"fmt"

	"ahcgo/ahc"
)

// The symbol Engine.hs imports.
//
//export host_log
func host_log(msg *C.char) {
	fmt.Printf("  [go] %s\n", C.GoString(msg))
}

const TEXT = "the quick brown fox jumps over the lazy dog\n" +
	"the dog barks and the fox runs\n"

func main() {
	p, _ := ahc.Primes(12)
	fmt.Printf("primes(12)   = %s\n", p)
	f, _ := ahc.Factorial(30)
	fmt.Printf("factorial(30)= %s\n", f)
	v, _ := ahc.EvalExpr("2 * (3 + 4) - 10 / 2")
	fmt.Printf("evalExpr     = %d\n", v)
	w, _ := ahc.WordFreq(TEXT)
	fmt.Printf("wordFreq     = %s\n", w)

	fmt.Println("analyze:")
	n, _ := ahc.Analyze(TEXT)
	fmt.Printf("  -> %d words\n", n)

	// A parse failure arrives as error, not a dead process.
	if bad, err := ahc.EvalExpr("2 +"); err != nil {
		fmt.Printf("evalExpr(bad): %v\n", err)
	} else {
		fmt.Printf("evalExpr(bad) = %d (unexpected)\n", bad)
	}

	alive, _ := ahc.EvalExpr("6*7")
	fmt.Printf("still alive  = %d\n", alive)
	g, _ := ahc.Greet("wörld λ")
	fmt.Printf("greet        = %s\n", g)
}
