package clean

import "example.com/analyzerfacts/relay"

func Correct() {
	relay.Relay("value=%d", 42)
}
