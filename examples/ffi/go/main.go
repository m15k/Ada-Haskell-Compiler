// Embedding the AHC-compiled MathLib from Go via the generated cgo
// package (ahc.go); the wrapper serializes calls onto one locked OS
// thread, and runtime errors inside the library arrive as error.
package main

import (
	"fmt"

	"ahcgo/ahc"
)

func main() {
	sq, _ := ahc.Square(12)
	fmt.Printf("square(12) = %d\n", sq)
	fb, _ := ahc.Hs_fib(90)
	fmt.Printf("fib(90) = %d\n", fb)
	g, _ := ahc.Greet("Go")
	fmt.Println(g)
	st, _ := ahc.SumTo(100)
	fmt.Printf("sumTo(100) = %d\n", st)
	if _, err := ahc.Boom(7); err != nil {
		fmt.Println("caught:", err)
	}
	sq6, _ := ahc.Square(6)
	fmt.Printf("square(6) = %d\n", sq6)
}
