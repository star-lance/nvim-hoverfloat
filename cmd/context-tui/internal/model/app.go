package model

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"sync"
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

// ConnectionState represents the current connection status
type ConnectionState int

const (
	Disconnected ConnectionState = iota
	Connecting
	Connected
	Reconnecting
)

// Custom message types
type ContinuePollingMsg struct{}
type ConnectionStateChangedMsg struct {
	State ConnectionState
}
type HeartbeatMsg struct {
	Timestamp int64
}
type TUIReadyMsg struct{} // New message type for readiness signaling

// MessageBridge handles thread-safe communication between goroutines and Bubble Tea
type MessageBridge struct {
	messages chan tea.Msg
	mu       sync.RWMutex
}

func NewMessageBridge() *MessageBridge {
	return &MessageBridge{
		messages: make(chan tea.Msg, 200), // Buffered channel for message queue
	}
}

// SendMessage queues a message to be sent to the main loop
func (mb *MessageBridge) SendMessage(msg tea.Msg) {
	select {
	case mb.messages <- msg:
		// Message queued successfully
	default:
		// Channel full, drop oldest messages to prevent blocking
		select {
		case <-mb.messages:
			mb.messages <- msg
		default:
		}
	}
}

// CheckMessages returns a command that polls for queued messages
func (mb *MessageBridge) CheckMessages() tea.Cmd {
	return func() tea.Msg {
		select {
		case msg := <-mb.messages:
			return msg
		default:
			return ContinuePollingMsg{}
		}
	}
}

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

	// Persistent socket communication
	socketPath        string
	socketListener    net.Listener
	clientConn        net.Conn
	connMutex         sync.RWMutex
	connectionState   ConnectionState
	messageBridge     *MessageBridge
	heartbeatTimer    *time.Timer
	connectionTimeout time.Duration

	// Readiness signaling
	readinessSignaled bool
	readinessMutex    sync.Mutex

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

// convertSocketContextToModel converts socket.ContextData to model.Context
func convertSocketContextToModel(socketData *socket.ContextData) *Context {
	if socketData == nil {
		return nil
	}

	return &Context{
		File:            socketData.File,
		Line:            socketData.Line,
		Col:             socketData.Col,
		Timestamp:       socketData.Timestamp,
		Hover:           socketData.Hover,
		Definition:      socketData.Definition,
		ReferencesCount: socketData.ReferencesCount,
		References:      socketData.References,
		ReferencesMore:  socketData.ReferencesMore,
		TypeDefinition:  socketData.TypeDefinition,
	}
}

// NewApp creates a new application model
func NewApp(socketPath string) *App {
	return &App{
		socketPath:        socketPath,
		ShowHover:         true,
		ShowReferences:    true,
		ShowDefinition:    true,
		ShowTypeInfo:      true,
		Focus:             FocusHover,
		styles:            styles.New(),
		messageBridge:     NewMessageBridge(),
		connectionState:   Disconnected,
		connectionTimeout: 30 * time.Second,
		readinessSignaled: false,
	}
}

// Init initializes the application
func (m *App) Init() tea.Cmd {
	return tea.Batch(
		m.startSocketServer(),
		tea.EnterAltScreen,
		m.messageBridge.CheckMessages(),
	)
}

// signalReadiness sends the readiness signal to stdout (called after socket setup)
func (m *App) signalReadiness() {
	m.readinessMutex.Lock()
	defer m.readinessMutex.Unlock()

	if m.readinessSignaled {
		return // Already signaled
	}

	// Signal readiness to parent (Neovim) via stdout
	fmt.Println("TUI_READY")
	os.Stdout.Sync() // Ensure immediate flush

	m.readinessSignaled = true
}

// Update handles messages and updates the model
func (m *App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.Width = msg.Width
		m.Height = msg.Height
		m.Ready = true
		return m, m.messageBridge.CheckMessages()

	case tea.KeyMsg:
		return m.handleKeyPress(msg)

	case socket.ContextUpdateMsg:
		// Convert socket.ContextData to model.Context
		m.Context = convertSocketContextToModel(msg.Data)
		m.LastUpdate = time.Now()
		m.ErrorMsg = ""
		return m, m.messageBridge.CheckMessages()

	case socket.ErrorMsg:
		m.ErrorMsg = string(msg)
		return m, m.messageBridge.CheckMessages()

	case ConnectionStateChangedMsg:
		m.setConnectionState(msg.State)
		
		// Signal readiness when socket is ready and accepting connections
		if msg.State == Connecting {
			// Socket server is now ready - signal to parent
			m.signalReadiness()
		}
		
		return m, m.messageBridge.CheckMessages()

	case TUIReadyMsg:
		// Handle explicit readiness message if needed
		m.signalReadiness()
		return m, m.messageBridge.CheckMessages()

	case HeartbeatMsg:
		// Update last heartbeat time
		return m, m.messageBridge.CheckMessages()

	case ContinuePollingMsg:
		// Continue polling for messages
		return m, m.messageBridge.CheckMessages()

	default:
		return m, m.messageBridge.CheckMessages()
	}
}

// handleKeyPress processes keyboard input
func (m *App) handleKeyPress(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Global keys
	switch msg.String() {
	case "ctrl+c", "q":
		return m, tea.Quit
	}

	// Content navigation and toggles
	switch msg.String() {
	case "h", "left":
		return m.navigateLeft(), m.messageBridge.CheckMessages()
	case "j", "down":
		return m.navigateDown(), m.messageBridge.CheckMessages()
	case "k", "up":
		return m.navigateUp(), m.messageBridge.CheckMessages()
	case "l", "right":
		return m.navigateRight(), m.messageBridge.CheckMessages()
	case "enter", " ":
		return m.toggleCurrentField(), m.messageBridge.CheckMessages()
	case "H":
		m.ShowHover = !m.ShowHover
		return m, m.messageBridge.CheckMessages()
	case "R":
		m.ShowReferences = !m.ShowReferences
		return m, m.messageBridge.CheckMessages()
	case "D":
		m.ShowDefinition = !m.ShowDefinition
		return m, m.messageBridge.CheckMessages()
	case "T":
		m.ShowTypeInfo = !m.ShowTypeInfo
		return m, m.messageBridge.CheckMessages()
	}

	return m, m.messageBridge.CheckMessages()
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

	connected := m.getConnectionState() == Connected

	content := view.Render(m.Width, m.Height, &view.ViewData{
		Context:        contextData,
		ErrorMsg:       m.ErrorMsg,
		Connected:      connected,
		LastUpdate:     m.LastUpdate,
		Focus:          int(m.Focus),
		ShowHover:      m.ShowHover,
		ShowReferences: m.ShowReferences,
		ShowDefinition: m.ShowDefinition,
		ShowTypeInfo:   m.ShowTypeInfo,
		MenuVisible:    false,
		MenuSelection:  0,
		// Viewport fields removed
		HoverViewport:      nil,
		ReferencesViewport: nil,
		DefinitionViewport: nil,
		TypeInfoViewport:   nil,
	}, m.styles)

	return content
}

// Connection state management (thread-safe)
func (m *App) setConnectionState(state ConnectionState) {
	m.connMutex.Lock()
	defer m.connMutex.Unlock()
	m.connectionState = state
}

func (m *App) getConnectionState() ConnectionState {
	m.connMutex.RLock()
	defer m.connMutex.RUnlock()
	return m.connectionState
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

		// Start accepting connections in background
		go m.acceptConnections()

		// Signal that socket server is ready for connections
		return ConnectionStateChangedMsg{State: Connecting}
	}
}

// acceptConnections runs in a goroutine to handle incoming connections
func (m *App) acceptConnections() {
	for {
		conn, err := m.socketListener.Accept()
		if err != nil {
			// Listener closed, exit gracefully
			m.messageBridge.SendMessage(socket.ErrorMsg("Socket listener closed"))
			return
		}

		// Handle new connection
		m.handleNewConnection(conn)
	}
}

// handleNewConnection sets up a new client connection
func (m *App) handleNewConnection(conn net.Conn) {
	m.connMutex.Lock()

	// Close existing connection if any
	if m.clientConn != nil {
		m.clientConn.Close()
	}

	m.clientConn = conn
	m.connectionState = Connected
	m.connMutex.Unlock()

	// Notify main loop of connection
	m.messageBridge.SendMessage(ConnectionStateChangedMsg{State: Connected})

	// Start handling this connection in a goroutine
	go m.handlePersistentConnection(conn)
}

// handlePersistentConnection manages the lifecycle of a persistent connection
func (m *App) handlePersistentConnection(conn net.Conn) {
	defer func() {
		conn.Close()
		m.connMutex.Lock()
		if m.clientConn == conn {
			m.clientConn = nil
			m.connectionState = Disconnected
		}
		m.connMutex.Unlock()

		// Notify main loop of disconnection
		m.messageBridge.SendMessage(ConnectionStateChangedMsg{State: Disconnected})
	}()

	// Set up buffered reader for newline-delimited messages
	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024) // 64KB initial, 1MB max

	// Set initial read timeout
	conn.SetReadDeadline(time.Now().Add(m.connectionTimeout))

	for scanner.Scan() {
		// Reset read timeout on each message
		conn.SetReadDeadline(time.Now().Add(m.connectionTimeout))

		line := scanner.Text()
		if line == "" {
			continue
		}

		// Parse JSON message
		var msg socket.Message
		if err := json.Unmarshal([]byte(line), &msg); err != nil {
			m.messageBridge.SendMessage(socket.ErrorMsg(fmt.Sprintf("Failed to parse message: %v", err)))
			continue
		}

		// Handle different message types
		switch msg.Type {
		case "context_update":
			if contextData, ok := msg.ExtractContextData(); ok {
				m.messageBridge.SendMessage(socket.ContextUpdateMsg{Data: contextData})
			} else {
				m.messageBridge.SendMessage(socket.ErrorMsg("Failed to extract context data from message"))
			}

		case "ping":
			if pingData, ok := msg.ExtractPingData(); ok {
				m.handlePing(conn, pingData.Timestamp)
			} else {
				// Fallback to message timestamp
				m.handlePing(conn, msg.Timestamp)
			}

		case "disconnect":
			// Client requested clean disconnect
			return

		case "error":
			if errorData, ok := msg.ExtractErrorData(); ok {
				m.messageBridge.SendMessage(socket.ErrorMsg(errorData.Error))
			} else {
				m.messageBridge.SendMessage(socket.ErrorMsg("Unknown error occurred"))
			}

		default:
			// Unknown message type, log but continue
			m.messageBridge.SendMessage(socket.ErrorMsg(fmt.Sprintf("Unknown message type: %s", msg.Type)))
		}
	}

	// Check for scanner errors
	if err := scanner.Err(); err != nil {
		m.messageBridge.SendMessage(socket.ErrorMsg(fmt.Sprintf("Connection error: %v", err)))
	}
}

// handlePing responds to ping messages with pong
func (m *App) handlePing(conn net.Conn, clientTimestamp int64) {
	pong := map[string]interface{}{
		"type":             "pong",
		"timestamp":        time.Now().UnixMilli(),
		"client_timestamp": clientTimestamp,
	}

	data, err := json.Marshal(pong)
	if err != nil {
		return
	}

	// Send pong response with newline delimiter
	conn.Write(append(data, '\n'))

	// Update heartbeat in main loop
	m.messageBridge.SendMessage(HeartbeatMsg{Timestamp: time.Now().UnixMilli()})
}

// sendToClient sends a message to the connected client (if any)
func (m *App) sendToClient(message interface{}) error {
	m.connMutex.RLock()
	conn := m.clientConn
	m.connMutex.RUnlock()

	if conn == nil {
		return fmt.Errorf("no client connected")
	}

	data, err := json.Marshal(message)
	if err != nil {
		return fmt.Errorf("failed to marshal message: %v", err)
	}

	// Send with newline delimiter
	_, err = conn.Write(append(data, '\n'))
	if err != nil {
		// Connection failed, will be cleaned up by connection handler
		return fmt.Errorf("failed to write to connection: %v", err)
	}

	return nil
}

// GetConnectionStatus returns current connection information
func (m *App) GetConnectionStatus() map[string]interface{} {
	m.connMutex.RLock()
	defer m.connMutex.RUnlock()

	return map[string]interface{}{
		"state":       m.connectionState,
		"connected":   m.connectionState == Connected,
		"socket_path": m.socketPath,
		"last_update": m.LastUpdate,
	}
}
