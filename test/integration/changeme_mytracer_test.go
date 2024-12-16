// This is a sample integration test file to serve as a guide for implementation.
// Refer to this blog: https://www.inspektor-gadget.io/blog/2024/06/introducing-the-new-testing-framework-for-image-based-gadgets.

package tests

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"

	gadgettesting "github.com/inspektor-gadget/inspektor-gadget/gadgets/testing"
	ebpftypes "github.com/inspektor-gadget/inspektor-gadget/pkg/operators/ebpf/types"
	igtesting "github.com/inspektor-gadget/inspektor-gadget/pkg/testing"
	"github.com/inspektor-gadget/inspektor-gadget/pkg/testing/containers"
	igrunner "github.com/inspektor-gadget/inspektor-gadget/pkg/testing/ig"
	"github.com/inspektor-gadget/inspektor-gadget/pkg/testing/match"
	"github.com/inspektor-gadget/inspektor-gadget/pkg/testing/utils"
)

// ExpectedMyTracerEvent represents the structure of the expected output
// from the tracer. It helps in validating the actual output.
type ExpectedMyTracerEvent struct {
	Proc  ebpftypes.Process `json:"proc"`
	Fd    uint32            `json:"fd"`
	FName string            `json:"fname"`
	// Add additional expected fields as necessary
}

func TestMyTracerGadget(t *testing.T) {
	// Ensure required environment variables are set; skip test otherwise.
	gadgettesting.RequireEnvironmentVariables(t)
	// Initialize utilities for the test.
	utils.InitTest(t)

	// Create a container factory to manage container lifecycle during the test.
	containerFactory, err := containers.NewContainerFactory(utils.Runtime)
	require.NoError(t, err, "Failed to create a new container factory")

	// Define the test container's name and image.
	containerName := "test-mytracer"
	containerImage := "base-container-image" // Replace with the actual container image to be used.

	// Configure the test container with the desired command and options.
	testContainer := containerFactory.NewContainer(
		containerName,
		"desired command for execution", // Replace with the actual command to execute in the container.
		containers.WithContainerImage(containerImage),
	)

	// Start the test container and defer its cleanup.
	testContainer.Start(t)
	t.Cleanup(func() {
		testContainer.Stop(t)
	})

	// Configure options for running the tracer gadget.
	runnerOpts := []igrunner.Option{
		// Specify runtime and set a timeout for the tracer execution.
		igrunner.WithFlags(fmt.Sprintf("-r=%s", utils.Runtime), "--timeout=5"),

		// Provide a validation function to check the tracer's output against expectations.
		igrunner.WithValidateOutput(func(t *testing.T, output string) {
			// Define the expected event structure.
			expectedEntry := &ExpectedMyTracerEvent{
				Proc:  utils.BuildProc("cat", 1000, 1111),
				FName: "/dev/null",
				Fd:    3,
				// Add additional expected fields as necessary.
			}

			// Define a normalization function if any field requires preprocessing before comparison.
			normalize := func(e *ExpectedMyTracerEvent) {
				// Example: Normalize fields such as timestamps or dynamic values.
			}

			// Match actual output with the expected entry.
			match.MatchEntries(t, match.JSONMultiObjectMode, output, normalize, expectedEntry)
		}),
	}

	// Define the test steps to run the tracer gadget.
	testSteps := []igtesting.TestStep{
		igrunner.New("mytracer", runnerOpts...), // Replace "mytracer" with the actual gadget name.
	}

	// Execute the test steps.
	igtesting.RunTestSteps(testSteps, t, nil)
}
