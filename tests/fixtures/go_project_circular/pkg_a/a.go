package pkg_a

import (
	"fmt"

	"github.com/test/circular/pkg_b"
)

func Hello() string {
	return fmt.Sprintf("hello from A, B says: %s", pkg_b.Greet())
}
