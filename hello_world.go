package main

import "fmt"

func main() {
	// Perennial models only fmt.Print, Printf, Sprintf and Errorf; it doesn't
	// translate Println, so proofs couldn't reason about a call to it.
	fmt.Print("Hello, world!\n")
}
