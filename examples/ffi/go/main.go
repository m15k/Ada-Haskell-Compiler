// Embedding the AHC-compiled MathLib from Go via the generated cgo
// package (ahc.go); the wrapper serializes calls onto one locked OS
// thread, so plain goroutine code just works.
package main

import (
	"fmt"

	"ahcgo/ahc"
)

func main() {
	fmt.Printf("square(12) = %d\n", ahc.Square(12))
	fmt.Printf("fib(90) = %d\n", ahc.Hs_fib(90))
	fmt.Println(ahc.Greet("Go"))
	fmt.Printf("sumTo(100) = %d\n", ahc.SumTo(100))
}
