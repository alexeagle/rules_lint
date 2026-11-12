package consumer

import "example.com/analyzerfacts/relay"

func Broken() {
	relay.Relay("value=%d", "not-an-integer")
}
