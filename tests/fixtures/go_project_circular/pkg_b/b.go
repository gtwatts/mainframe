package pkg_b

import (
	"fmt"

	"github.com/test/circular/pkg_a"
)

func Greet() string {
	return fmt.Sprintf("greet from B, A says: %s", pkg_a.Hello())
}
