package trivy_test

import (
	"testing"

	"github.com/docker/sbx-kits-contrib/tck"
	"github.com/stretchr/testify/require"
)

func TestTrivyTCK(t *testing.T) {
	suite, err := tck.NewSuiteFromDir(".")
	require.NoError(t, err)
	suite.RunAll(t)
}
