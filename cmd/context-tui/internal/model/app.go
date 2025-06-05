package model

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/star-lance/nvim-hoverfloat/cmd/context-tui/internal/socket"
	"github.com/star-lance/nvim-hoverfloat/cmd/context-tui/internal/styles"
	"github.com/star-lance/nvim-hoverfloat/cmd/context-tui/internal/view"
)

// FocusArea represents the currently focused section
type FocusArea int

const (
	FocusHover FocusArea = iota
	FocusReferences
	FocusDefinition
	FocusTypeDefinition
)

// App represents the main application model
type App struct {
	// Display state
	Width  int
	Height int
	Ready  bool

	// Content state
	Context    *Context
	LastUpdate time.Time
	ErrorMsg   string

	// Interactive state
	Focus          FocusArea
	ShowHover      bool
	ShowReferences bool
	ShowDefinition bool
	ShowTypeInfo   bool

	// Menu state
	MenuVisible   bool
	MenuSelection int

	// Socket communication
	socketPath     string
	socketListener net.Listener
	connected      bool

	// Styles
	styles *styles.Styles
}

// Context represents LSP context data
type Context struct {
	File            string                `json:"file"`
	Line            int                   `json:"line"`
	Col             int                   `json:"col"`
	Timestamp       int64                 `json:"timestamp"`
	Hover           []string              `json:"hover,omitempty"`
	Definition      *socket.LocationInfo  `json:"definition,omitempty"`
	ReferencesCount int                   `json:"references_count,omitempty"`
	References      []socket.LocationInfo `json:"references,omitempty"`
	ReferencesMore  int                   `json:"references_more,omitempty"`
	TypeDefinition  *socket.LocationInfo  `json:"type_definition,omitempty"`
}

// NewApp creates a new application model
func NewApp(socketPath string) *App {
	return &App{
		socketPath:     socketPath,
		ShowHover:      true,
		ShowReferences: true,
		ShowDefinition: true,
		ShowTypeInfo:   true,
		Focus:          FocusHover,
		styles:         styles.New(),
	}
}

// Init initializes the application
func (m *App) Init() tea.Cmd {
	return tea.Batch(
		m.startSocketServer(),
		tea.EnterAltScreen,
	)
}

// Update handles messages and updates the model
func (m *App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.Width = msg.Width
		m.Height = msg.Height
		m.Ready = true
		return m, nil

	case tea.KeyMsg:
		return m.handleKeyPress(msg)

	case socket.ContextUpdateMsg:
		m.Context = (*Context)(msg.Data)
		m.LastUpdate = time.Now()
		m.ErrorMsg = ""
		// Continue listening for more messages and force a redraw
		return m, tea.Batch(m.listenForMessages(), tea.Tick(time.Millisecond, func(time.Time) tea.Msg { return nil }))

	case socket.ErrorMsg:
		m.ErrorMsg = string(msg)
		// Continue listening for more messages and force a redraw
		return m, tea.Batch(m.listenForMessages(), tea.Tick(time.Millisecond, func(time.Time) tea.Msg { return nil }))

	case socket.ConnectionMsg:
		m.connected = bool(msg)
		// Start listening for messages now that socket is connected
		return m, m.listenForMessages()

	default:
		return m, nil
	}
}

// handleKeyPress processes keyboard input
func (m *App) handleKeyPress(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Global keys
	switch msg.String() {
	case "ctrl+c", "q":
		return m, tea.Quit
	case "?", "F1":
		m.MenuVisible = !m.MenuVisible
		return m, nil
	}

	// Menu navigation
	if m.MenuVisible {
		switch msg.String() {
		case "j", "down":
			m.MenuSelection = (m.MenuSelection + 1) % 4
		case "k", "up":
			m.MenuSelection = (m.MenuSelection - 1 + 4) % 4
		case "enter", " ":
			return m.toggleMenuItem(), nil
		case "esc":
			m.MenuVisible = false
		}
		return m, nil
	}

	// Content navigation and toggles
	switch msg.String() {
	case "h", "left":
		return m.navigateLeft(), nil
	case "j", "down":
		return m.navigateDown(), nil
	case "k", "up":
		return m.navigateUp(), nil
	case "l", "right":
		return m.navigateRight(), nil
	case "enter", " ":
		return m.toggleCurrentField(), nil
	case "H":
		m.ShowHover = !m.ShowHover
		return m, nil
	case "R":
		m.ShowReferences = !m.ShowReferences
		return m, nil
	case "D":
		m.ShowDefinition = !m.ShowDefinition
		return m, nil
	case "T":
		m.ShowTypeInfo = !m.ShowTypeInfo
		return m, nil
	case "r":
		// Refresh - request new data (mock for now)
		return m, nil
	}

	return m, nil
}

// Navigation methods
func (m *App) navigateDown() *App {
	areas := m.getVisibleAreas()
	if len(areas) == 0 {
		return m
	}

	current := m.findCurrentIndex(areas)
	m.Focus = areas[(current+1)%len(areas)]
	return m
}

func (m *App) navigateUp() *App {
	areas := m.getVisibleAreas()
	if len(areas) == 0 {
		return m
	}

	current := m.findCurrentIndex(areas)
	m.Focus = areas[(current-1+len(areas))%len(areas)]
	return m
}

func (m *App) navigateLeft() *App {
	// Could be used for horizontal navigation in the future
	return m
}

func (m *App) navigateRight() *App {
	// Could be used for horizontal navigation in the future
	return m
}

func (m *App) getVisibleAreas() []FocusArea {
	var areas []FocusArea
	if m.ShowHover {
		areas = append(areas, FocusHover)
	}
	if m.ShowReferences {
		areas = append(areas, FocusReferences)
	}
	if m.ShowDefinition {
		areas = append(areas, FocusDefinition)
	}
	if m.ShowTypeInfo {
		areas = append(areas, FocusTypeDefinition)
	}
	return areas
}

func (m *App) findCurrentIndex(areas []FocusArea) int {
	for i, area := range areas {
		if area == m.Focus {
			return i
		}
	}
	return 0
}

// toggleCurrentField toggles the currently focused field
func (m *App) toggleCurrentField() *App {
	switch m.Focus {
	case FocusHover:
		m.ShowHover = !m.ShowHover
	case FocusReferences:
		m.ShowReferences = !m.ShowReferences
	case FocusDefinition:
		m.ShowDefinition = !m.ShowDefinition
	case FocusTypeDefinition:
		m.ShowTypeInfo = !m.ShowTypeInfo
	}
	return m
}

// toggleMenuItem toggles the selected menu item
func (m *App) toggleMenuItem() *App {
	switch m.MenuSelection {
	case 0:
		m.ShowHover = !m.ShowHover
	case 1:
		m.ShowReferences = !m.ShowReferences
	case 2:
		m.ShowDefinition = !m.ShowDefinition
	case 3:
		m.ShowTypeInfo = !m.ShowTypeInfo
	}
	return m
}

// View renders the application
func (m *App) View() string {
	if !m.Ready {
		return "Loading..."
	}

	// Create the main view
	var contextData *socket.ContextData
	if m.Context != nil {
		contextData = &socket.ContextData{
			File:            m.Context.File,
			Line:            m.Context.Line,
			Col:             m.Context.Col,
			Timestamp:       m.Context.Timestamp,
			Hover:           m.Context.Hover,
			Definition:      m.Context.Definition,
			ReferencesCount: m.Context.ReferencesCount,
			References:      m.Context.References,
			ReferencesMore:  m.Context.ReferencesMore,
			TypeDefinition:  m.Context.TypeDefinition,
		}
	}

	content := view.Render(m.Width, m.Height, &view.ViewData{
		Context:        contextData,
		ErrorMsg:       m.ErrorMsg,
		Connected:      m.connected,
		LastUpdate:     m.LastUpdate,
		Focus:          int(m.Focus),
		ShowHover:      m.ShowHover,
		ShowReferences: m.ShowReferences,
		ShowDefinition: m.ShowDefinition,
		ShowTypeInfo:   m.ShowTypeInfo,
		MenuVisible:    m.MenuVisible,
		MenuSelection:  m.MenuSelection,
	}, m.styles)

	return content
}

// startSocketServer initializes the Unix socket server
func (m *App) startSocketServer() tea.Cmd {
	return func() tea.Msg {
		// Remove existing socket file
		os.Remove(m.socketPath)

		// Create Unix socket
		listener, err := net.Listen("unix", m.socketPath)
		if err != nil {
			return socket.ErrorMsg(fmt.Sprintf("Failed to create socket: %v", err))
		}

		m.socketListener = listener

		return socket.ConnectionMsg(true)
	}
}

// listenForMessages returns a command that listens for incoming socket messages
func (m *App) listenForMessages() tea.Cmd {
	return func() tea.Msg {
		if m.socketListener == nil {
			return nil
		}

		conn, err := m.socketListener.Accept()
		if err != nil {
			return socket.ErrorMsg("Socket connection failed")
		}

		// Handle ONE message per connection, then close
		decoder := json.NewDecoder(conn)
		var msg socket.Message
		if err := decoder.Decode(&msg); err != nil {
			conn.Close()
			return socket.ErrorMsg("Failed to decode message")
		}
		
		// Close connection after reading one message
		conn.Close()

		// Return the message to the main program
		if msg.Type == "context_update" {
			return socket.ContextUpdateMsg{Data: (*socket.ContextData)(&msg.Data)}
		}

		return nil
	}
}


