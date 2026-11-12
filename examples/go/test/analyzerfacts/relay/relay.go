package relay

import "fmt"

func Relay(format string, args ...any) {
	fmt.Printf(format, args...)
}

// Dependencies supply facts, but their diagnostics must not reach the root report.
func Redundant(x int) bool {
	return x == 1 || x == 1
}
