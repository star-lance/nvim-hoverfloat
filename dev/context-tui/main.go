package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Simple message types for dev testing
type Message struct {
	Type      string      `json:"type"`
	Timestamp int64       `json:"timestamp"`
	Data      ContextData `json:"data"`
}

type ContextData struct {
	File             string         `json:"file"`
	Line             int            `json:"line"`
	Col              int            `json:"col"`
	Timestamp        int64          `json:"timestamp"`
	Hover            []string       `json:"hover,omitempty"`
	Definition       *LocationInfo  `json:"definition,omitempty"`
	ReferencesCount  int            `json:"references_count,omitempty"`
	References       []LocationInfo `json:"references,omitempty"`
	ReferencesMore   int            `json:"references_more,omitempty"`
	TypeDefinition   *LocationInfo  `json:"type_definition,omitempty"`
}

type LocationInfo struct {
	File string `json:"file"`
	Line int    `json:"line"`
	Col  int    `json:"col"`
}

// Bubble Tea messages
type ContextUpdateMsg struct {
	Data *ContextData
}

type ErrorMsg string

type ConnectionMsg bool

// Simple model for dev testing
type model struct {
	context     *ContextData
	width       int
	height      int
	ready       bool
	connected   bool
	error       string
	lastUpdate  time.Time
	socketPath  string
	listener    net.Listener
	
	// Simple styles
	headerStyle    lipgloss.Style
	contentStyle   lipgloss.Style
	errorStyle     lipgloss.Style
	successStyle   lipgloss.Style
}

func initialModel(socketPath string) model {
	return model{
		socketPath:   socketPath,
		headerStyle:  lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#7aa2f7")),
		contentStyle: lipgloss.NewStyle().Foreground(lipgloss.Color("#c0caf5")),
		errorStyle:   lipgloss.NewStyle().Foreground(lipgloss.Color("#f7768e")),
		successStyle: lipgloss.NewStyle().Foreground(lipgloss.Color("#9ece6a")),
	}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(
		m.startSocketServer(),
		tea.EnterAltScreen,
	)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.ready = true
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			if m.listener != nil {
				m.listener.Close()
			}
			return m, tea.Quit
		case "r":
			// Manual refresh
			return m, nil
		case "c":
			// Clear context
			m.context = nil
			m.error = ""
			return m, nil
		}

	case ContextUpdateMsg:
		m.context = msg.Data
		m.lastUpdate = time.Now()
		m.error = ""
		return m, nil

	case ErrorMsg:
		m.error = string(msg)
		return m, nil

	case ConnectionMsg:
		m.connected = bool(msg)
		return m, nil
	}

	return m, nil
}

func (m model) View() string {
	if !m.ready {
		return "Loading..."
	}

	var content []string
	
	// Header
	header := m.headerStyle.Render("🔍 LSP Context TUI (Dev Version)")
	content = append(content, header)
	content = append(content, "")

	// Connection status
	status := "❌ Disconnected"
	if m.connected {
		status = "✅ Connected"
	}
	content = append(content, m.contentStyle.Render("Status: "+status))
	content = append(content, m.contentStyle.Render("Socket: "+m.socketPath))
	
	if !m.lastUpdate.IsZero() {
		content = append(content, m.contentStyle.Render("Last update: "+m.lastUpdate.Format("15:04:05")))
	}
	
	content = append(content, "")

	// Error display
	if m.error != "" {
		content = append(content, m.errorStyle.Render("Error: "+m.error))
		content = append(content, "")
	}

	// Context data
	if m.context != nil {
		content = append(content, m.headerStyle.Render("📄 Current File:"))
		content = append(content, m.contentStyle.Render(fmt.Sprintf("  %s:%d:%d", 
			m.context.File, m.context.Line, m.context.Col)))
		content = append(content, "")

		// Hover info
		if len(m.context.Hover) > 0 {
			content = append(content, m.headerStyle.Render("📖 Hover:"))
			for i, line := range m.context.Hover {
				if i >= 8 { // Limit lines for dev view
					content = append(content, m.contentStyle.Render("  ... (truncated)"))
					break
				}
				content = append(content, m.contentStyle.Render("  "+line))
			}
			content = append(content, "")
		}

		// Definition
		if m.context.Definition != nil {
			content = append(content, m.headerStyle.Render("📍 Definition:"))
			content = append(content, m.contentStyle.Render(fmt.Sprintf("  %s:%d:%d", 
				m.context.Definition.File, m.context.Definition.Line, m.context.Definition.Col)))
			content = append(content, "")
		}

		// References
		if len(m.context.References) > 0 {
			refText := "reference"
			if m.context.ReferencesCount != 1 {
				refText = "references"
			}
			content = append(content, m.headerStyle.Render(fmt.Sprintf("🔗 References (%d %s):", m.context.ReferencesCount, refText)))
			
			for i, ref := range m.context.References {
				if i >= 5 { // Limit for dev view
					if m.context.ReferencesMore > 0 {
						content = append(content, m.contentStyle.Render(fmt.Sprintf("  ... and %d more", m.context.ReferencesMore)))
					}
					break
				}
				content = append(content, m.contentStyle.Render(fmt.Sprintf("  • %s:%d", ref.File, ref.Line)))
			}
			content = append(content, "")
		}

		// Type definition
		if m.context.TypeDefinition != nil {
			content = append(content, m.headerStyle.Render("🎯 Type Definition:"))
			content = append(content, m.contentStyle.Render(fmt.Sprintf("  %s:%d:%d", 
				m.context.TypeDefinition.File, m.context.TypeDefinition.Line, m.context.TypeDefinition.Col)))
			content = append(content, "")
		}
	} else {
		content = append(content, m.contentStyle.Render("Waiting for context data..."))
		content = append(content, m.contentStyle.Render("Move your cursor in Neovim to see LSP information here."))
		content = append(content, "")
	}

	// Footer
	content = append(content, "")
	content = append(content, m.contentStyle.Render("Controls: q/Ctrl+C=quit, r=refresh, c=clear"))

	return lipgloss.JoinVertical(lipgloss.Left, content...)
}

func (m model) startSocketServer() tea.Cmd {
	return func() tea.Msg {
		// Remove existing socket
		os.Remove(m.socketPath)

		// Create listener
		listener, err := net.Listen("unix", m.socketPath)
		if err != nil {
			return ErrorMsg(fmt.Sprintf("Failed to create socket: %v", err))
		}

		// Store listener for cleanup
		program := tea.NewProgram(nil) // This is a hack, we need the program instance
		go func() {
			for {
				conn, err := listener.Accept()
				if err != nil {
					// Socket closed, exit gracefully
					return
				}

				// Handle connection
				go func(c net.Conn) {
					defer c.Close()
					decoder := json.NewDecoder(c)
					
					for {
						var msg Message
						if err := decoder.Decode(&msg); err != nil {
							return
						}

						if msg.Type == "context_update" {
							program.Send(ContextUpdateMsg{Data: &msg.Data})
						}
					}
				}(conn)
			}
		}()

		return ConnectionMsg(true)
	}
}

func main() {
	// Get socket path from args or use default
	socketPath := "/tmp/nvim_context.sock"
	if len(os.Args) > 1 {
		socketPath = os.Args[1]
	}

	// Create model
	m := initialModel(socketPath)

	// Create program
	p := tea.NewProgram(
		m,
		tea.WithAltScreen(),
	)

	// Store listener in model (hack for cleanup)
	if model, ok := m.(model); ok {
		defer func() {
			if model.listener != nil {
				model.listener.Close()
			}
			os.Remove(socketPath)
		}()
	}

	// Run
	if _, err := p.Run(); err != nil {
		log.Fatal(err)
	}
}
