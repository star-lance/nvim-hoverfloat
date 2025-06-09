package main

import (
	"fmt"
	"log"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/star-lance/nvim-hoverfloat/cmd/context-tui/internal/model"
)

func main() {
	// Get socket path from command line or use default
	socketPath := "/tmp/nvim_context.sock"
	if len(os.Args) > 1 {
		socketPath = os.Args[1]
	}

	// Create the initial model
	initialModel := model.NewApp(socketPath)

	// Create the Bubble Tea program
	p := tea.NewProgram(
		initialModel,
		tea.WithAltScreen(),       // Use alternate screen buffer
		tea.WithMouseCellMotion(), // Enable mouse support
	)

	// Run the program
	if _, err := p.Run(); err != nil {
		log.Printf("Error running TUI: %v", err)
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}
}
