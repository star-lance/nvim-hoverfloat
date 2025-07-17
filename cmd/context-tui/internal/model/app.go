package model

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"nvim-hoverfloat/cmd/context-tui/internal/socket"
	"nvim-hoverfloat/cmd/context-tui/internal/styles"
	"nvim-hoverfloat/cmd/context-tui/internal/view"
)

// FocusArea represents the currently focused section
type FocusArea int

const (
	FocusHover FocusArea = iota
	FocusReferences
	FocusDefinition
	FocusTypeDefinition
)

// SelectionMode represents text selection state
type SelectionMode int

const (
	SelectionNone SelectionMode = iota
	SelectionStarted
	SelectionActive
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
type ViewportReadyMsg struct {
	Area FocusArea
}

// App represents the main application model with enhanced interactivity
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
	SectionHeights map[FocusArea]int // Dynamic section heights

	// Selection state
	SelectionMode  SelectionMode
	SelectionStart int
	SelectionEnd   int
	SelectedText   string

	// Viewports for scrollable content
	HoverViewport      viewport.Model
	ReferencesViewport viewport.Model
	DefinitionViewport viewport.Model
	TypeInfoViewport   viewport.Model
	viewportsReady     bool

	// Socket communication
	socketPath        string
	socketListener    net.Listener
	clientConn        net.Conn
	connMutex         sync.RWMutex
	connectionState   ConnectionState
	messageBridge     *MessageBridge
	heartbeatTimer    *time.Timer
	connectionTimeout time.Duration

	// Readiness handling
	readinessHandled bool

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

// MessageBridge handles thread-safe communication
type MessageBridge struct {
	messages chan tea.Msg
	mu       sync.RWMutex
}

func NewMessageBridge() *MessageBridge {
	return &MessageBridge{
		messages: make(chan tea.Msg, 200),
	}
}

func (mb *MessageBridge) SendMessage(msg tea.Msg) {
	select {
	case mb.messages <- msg:
	default:
		// Channel full, drop oldest messages
		select {
		case <-mb.messages:
			mb.messages <- msg
		default:
		}
	}
}

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

// NewApp creates a new application model
func NewApp(socketPath string) *App {
	app := &App{
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
		SectionHeights:    make(map[FocusArea]int),
		SelectionMode:     SelectionNone,
	}

	// Initialize default section heights
	app.SectionHeights[FocusHover] = 10
	app.SectionHeights[FocusReferences] = 8
	app.SectionHeights[FocusDefinition] = 4
	app.SectionHeights[FocusTypeDefinition] = 4

	return app
}

// Init initializes the application
func (m *App) Init() tea.Cmd {
	// Send readiness signal immediately via a proper file descriptor
	m.signalReadiness()

	return tea.Batch(
		m.startSocketServer(),
		tea.EnterAltScreen,
		m.messageBridge.CheckMessages(),
	)
}

// signalReadiness sends readiness signal via a more reliable method
func (m *App) signalReadiness() {
	if m.readinessHandled {
		return
	}
	m.readinessHandled = true

	// Method 1: Write to stdout
	fmt.Println("TUI_READY")
	os.Stdout.Sync()

	// Method 2: Create a readiness file (more reliable)
	readyFile := fmt.Sprintf("/tmp/nvim_context_tui_%d.ready", os.Getpid())
	if file, err := os.Create(readyFile); err == nil {
		file.Close()
	}
}

// Update handles messages and updates the model
func (m *App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	// Update viewports if they're ready
	if m.viewportsReady {
		switch m.Focus {
		case FocusHover:
			newHover, cmd := m.HoverViewport.Update(msg)
			m.HoverViewport = newHover
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
		case FocusReferences:
			newRefs, cmd := m.ReferencesViewport.Update(msg)
			m.ReferencesViewport = newRefs
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
		case FocusDefinition:
			newDef, cmd := m.DefinitionViewport.Update(msg)
			m.DefinitionViewport = newDef
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
		case FocusTypeDefinition:
			newType, cmd := m.TypeInfoViewport.Update(msg)
			m.TypeInfoViewport = newType
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
		}
	}

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.Width = msg.Width
		m.Height = msg.Height
		m.Ready = true

		// Initialize viewports with proper sizes
		m.initializeViewports()
		return m, tea.Batch(append(cmds, m.messageBridge.CheckMessages())...)

	case tea.KeyMsg:
		cmd := m.handleKeyPress(msg)
		cmds = append(cmds, cmd)
		return m, tea.Batch(cmds...)

	case socket.ContextUpdateMsg:
		m.Context = convertSocketContextToModel(msg.Data)
		m.LastUpdate = time.Now()
		m.ErrorMsg = ""
		m.updateViewportContent()
		cmds = append(cmds, m.messageBridge.CheckMessages())
		return m, tea.Batch(cmds...)

	case socket.ErrorMsg:
		m.ErrorMsg = string(msg)
		cmds = append(cmds, m.messageBridge.CheckMessages())
		return m, tea.Batch(cmds...)

	case ConnectionStateChangedMsg:
		m.setConnectionState(msg.State)
		cmds = append(cmds, m.messageBridge.CheckMessages())
		return m, tea.Batch(cmds...)

	case ViewportReadyMsg:
		// Viewport is ready for the specified area
		cmds = append(cmds, m.messageBridge.CheckMessages())
		return m, tea.Batch(cmds...)

	case ContinuePollingMsg:
		cmds = append(cmds, m.messageBridge.CheckMessages())
		return m, tea.Batch(cmds...)

	default:
		cmds = append(cmds, m.messageBridge.CheckMessages())
		return m, tea.Batch(cmds...)
	}
}

// initializeViewports sets up the viewports with proper dimensions
func (m *App) initializeViewports() {
	if m.Width == 0 || m.Height == 0 {
		return
	}

	// Initialize each viewport
	m.HoverViewport = viewport.New(m.Width-4, m.SectionHeights[FocusHover])
	m.HoverViewport.Style = m.styles.SectionContent

	m.ReferencesViewport = viewport.New(m.Width-4, m.SectionHeights[FocusReferences])
	m.ReferencesViewport.Style = m.styles.SectionContent

	m.DefinitionViewport = viewport.New(m.Width-4, m.SectionHeights[FocusDefinition])
	m.DefinitionViewport.Style = m.styles.SectionContent

	m.TypeInfoViewport = viewport.New(m.Width-4, m.SectionHeights[FocusTypeDefinition])
	m.TypeInfoViewport.Style = m.styles.SectionContent

	m.viewportsReady = true
	m.updateViewportContent()
}

// updateViewportContent updates the content in all viewports
func (m *App) updateViewportContent() {
	if !m.viewportsReady || m.Context == nil {
		return
	}

	// Update hover viewport
	if m.Context.Hover != nil && len(m.Context.Hover) > 0 {
		hoverContent := strings.Join(m.Context.Hover, "\n")
		m.HoverViewport.SetContent(hoverContent)
	}

	// Update references viewport
	if m.Context.References != nil && len(m.Context.References) > 0 {
		var refLines []string
		for i, ref := range m.Context.References {
			refLines = append(refLines, fmt.Sprintf("%d. %s:%d:%d", i+1, ref.File, ref.Line, ref.Col))
		}
		if m.Context.ReferencesMore > 0 {
			refLines = append(refLines, fmt.Sprintf("\n... and %d more references", m.Context.ReferencesMore))
		}
		m.ReferencesViewport.SetContent(strings.Join(refLines, "\n"))
	}

	// Update definition viewport
	if m.Context.Definition != nil {
		defContent := fmt.Sprintf("Definition: %s:%d:%d",
			m.Context.Definition.File,
			m.Context.Definition.Line,
			m.Context.Definition.Col)
		m.DefinitionViewport.SetContent(defContent)
	}

	// Update type info viewport
	if m.Context.TypeDefinition != nil {
		typeContent := fmt.Sprintf("Type Definition: %s:%d:%d",
			m.Context.TypeDefinition.File,
			m.Context.TypeDefinition.Line,
			m.Context.TypeDefinition.Col)
		m.TypeInfoViewport.SetContent(typeContent)
	}
}

// handleKeyPress processes keyboard input with enhanced functionality
func (m *App) handleKeyPress(msg tea.KeyMsg) tea.Cmd {
	// Global keys
	switch msg.String() {
	case "ctrl+c", "q":
		return tea.Quit
	case "?", "f1":
		// Toggle help menu
		return nil
	case "ctrl+y":
		// Copy selected text to clipboard
		if m.SelectedText != "" {
			// In a real implementation, this would copy to system clipboard
			// For now, we'll just log it
			fmt.Fprintf(os.Stderr, "Copied: %s\n", m.SelectedText)
		}
		return nil
	}

	// Selection mode handling
	if m.SelectionMode != SelectionNone {
		return m.handleSelectionKeys(msg)
	}

	// Normal mode navigation
	switch msg.String() {
	case "h", "left":
		return m.navigateLeft()
	case "j", "down":
		return m.navigateDown()
	case "k", "up":
		return m.navigateUp()
	case "l", "right":
		return m.navigateRight()
	case "g":
		// Go to top of current viewport
		return m.goToTop()
	case "G":
		// Go to bottom of current viewport
		return m.goToBottom()
	case "ctrl+u":
		// Half page up
		return m.halfPageUp()
	case "ctrl+d":
		// Half page down
		return m.halfPageDown()
	case "enter", " ":
		return m.toggleCurrentField()
	case "v":
		// Enter visual selection mode
		m.SelectionMode = SelectionStarted
		m.SelectionStart = m.getCurrentViewport().YOffset
		return nil
	case "H":
		m.ShowHover = !m.ShowHover
		return nil
	case "R":
		m.ShowReferences = !m.ShowReferences
		return nil
	case "D":
		m.ShowDefinition = !m.ShowDefinition
		return nil
	case "T":
		m.ShowTypeInfo = !m.ShowTypeInfo
		return nil
	case "+", "=":
		// Increase current section height
		return m.resizeSection(2)
	case "-", "_":
		// Decrease current section height
		return m.resizeSection(-2)
	}

	return m.messageBridge.CheckMessages()
}

// handleSelectionKeys handles keys in selection mode
func (m *App) handleSelectionKeys(msg tea.KeyMsg) tea.Cmd {
	switch msg.String() {
	case "v", "escape":
		// Exit selection mode
		m.SelectionMode = SelectionNone
		m.SelectedText = ""
		return nil
	case "j", "down":
		m.SelectionEnd++
		m.updateSelectedText()
		return nil
	case "k", "up":
		m.SelectionEnd--
		m.updateSelectedText()
		return nil
	}
	return nil
}

// Viewport navigation methods
func (m *App) getCurrentViewport() *viewport.Model {
	switch m.Focus {
	case FocusHover:
		return &m.HoverViewport
	case FocusReferences:
		return &m.ReferencesViewport
	case FocusDefinition:
		return &m.DefinitionViewport
	case FocusTypeDefinition:
		return &m.TypeInfoViewport
	}
	return &m.HoverViewport
}

func (m *App) goToTop() tea.Cmd {
	vp := m.getCurrentViewport()
	vp.GotoTop()
	return nil
}

func (m *App) goToBottom() tea.Cmd {
	vp := m.getCurrentViewport()
	vp.GotoBottom()
	return nil
}

func (m *App) halfPageUp() tea.Cmd {
	vp := m.getCurrentViewport()
	vp.HalfViewUp()
	return nil
}

func (m *App) halfPageDown() tea.Cmd {
	vp := m.getCurrentViewport()
	vp.HalfViewDown()
	return nil
}

func (m *App) resizeSection(delta int) tea.Cmd {
	current := m.SectionHeights[m.Focus]
	newHeight := current + delta
	if newHeight < 3 {
		newHeight = 3
	}
	if newHeight > m.Height-10 {
		newHeight = m.Height - 10
	}
	m.SectionHeights[m.Focus] = newHeight
	m.initializeViewports()
	return nil
}

func (m *App) updateSelectedText() {
	// This would extract text from the current viewport
	// For now, just update the selection range
	m.SelectionMode = SelectionActive
}

// Navigation methods
func (m *App) navigateDown() tea.Cmd {
	areas := m.getVisibleAreas()
	if len(areas) == 0 {
		return nil
	}

	current := m.findCurrentIndex(areas)
	m.Focus = areas[(current+1)%len(areas)]
	return nil
}

func (m *App) navigateUp() tea.Cmd {
	areas := m.getVisibleAreas()
	if len(areas) == 0 {
		return nil
	}

	current := m.findCurrentIndex(areas)
	m.Focus = areas[(current-1+len(areas))%len(areas)]
	return nil
}

func (m *App) navigateLeft() tea.Cmd {
	vp := m.getCurrentViewport()
	vp.LineUp(1)
	return nil
}

func (m *App) navigateRight() tea.Cmd {
	vp := m.getCurrentViewport()
	vp.LineDown(1)
	return nil
}

func (m *App) getVisibleAreas() []FocusArea {
	var areas []FocusArea
	if m.ShowHover && m.Context != nil && len(m.Context.Hover) > 0 {
		areas = append(areas, FocusHover)
	}
	if m.ShowReferences && m.Context != nil && len(m.Context.References) > 0 {
		areas = append(areas, FocusReferences)
	}
	if m.ShowDefinition && m.Context != nil && m.Context.Definition != nil {
		areas = append(areas, FocusDefinition)
	}
	if m.ShowTypeInfo && m.Context != nil && m.Context.TypeDefinition != nil {
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

func (m *App) toggleCurrentField() tea.Cmd {
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
	return nil
}

// View renders the application
func (m *App) View() string {
	if !m.Ready {
		return "Loading..."
	}

	// Convert viewports to view.ViewportData
	var viewData = &view.ViewData{
		Context:        convertContextToSocket(m.Context),
		ErrorMsg:       m.ErrorMsg,
		Connected:      m.getConnectionState() == Connected,
		LastUpdate:     m.LastUpdate,
		Focus:          int(m.Focus),
		ShowHover:      m.ShowHover,
		ShowReferences: m.ShowReferences,
		ShowDefinition: m.ShowDefinition,
		ShowTypeInfo:   m.ShowTypeInfo,
		MenuVisible:    false,
		MenuSelection:  0,
	}

	// Pass actual viewports if ready
	if m.viewportsReady {
		viewData.HoverViewport = &m.HoverViewport
		viewData.ReferencesViewport = &m.ReferencesViewport
		viewData.DefinitionViewport = &m.DefinitionViewport
		viewData.TypeInfoViewport = &m.TypeInfoViewport
	}

	return view.Render(m.Width, m.Height, viewData, m.styles)
}

// Helper functions

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

func convertContextToSocket(context *Context) *socket.ContextData {
	if context == nil {
		return nil
	}

	return &socket.ContextData{
		File:            context.File,
		Line:            context.Line,
		Col:             context.Col,
		Timestamp:       context.Timestamp,
		Hover:           context.Hover,
		Definition:      context.Definition,
		ReferencesCount: context.ReferencesCount,
		References:      context.References,
		ReferencesMore:  context.ReferencesMore,
		TypeDefinition:  context.TypeDefinition,
	}
}

// Connection state management
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

// Socket server setup and management
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

func (m *App) acceptConnections() {
	for {
		conn, err := m.socketListener.Accept()
		if err != nil {
			m.messageBridge.SendMessage(socket.ErrorMsg("Socket listener closed"))
			return
		}

		// Handle new connection
		m.handleNewConnection(conn)
	}
}

func (m *App) handleNewConnection(conn net.Conn) {
	// Optimize socket for low-latency communication
	m.optimizeSocket(conn)

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

func (m *App) optimizeSocket(conn net.Conn) {
	if unixConn, ok := conn.(*net.UnixConn); ok {
		// Get underlying file descriptor for low-level optimizations
		file, err := unixConn.File()
		if err == nil {
			defer file.Close()
			fd := int(file.Fd())

			// Set optimal buffer sizes
			syscall.SetsockoptInt(fd, syscall.SOL_SOCKET, syscall.SO_RCVBUF, 32*1024)
			syscall.SetsockoptInt(fd, syscall.SOL_SOCKET, syscall.SO_SNDBUF, 32*1024)
			syscall.SetsockoptInt(fd, syscall.SOL_SOCKET, syscall.SO_REUSEADDR, 1)
		}
	}
}

func (m *App) handlePersistentConnection(conn net.Conn) {
	defer func() {
		conn.Close()
		m.connMutex.Lock()
		if m.clientConn == conn {
			m.clientConn = nil
			m.connectionState = Disconnected
		}
		m.connMutex.Unlock()

		m.messageBridge.SendMessage(ConnectionStateChangedMsg{State: Disconnected})
	}()

	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	conn.SetReadDeadline(time.Now().Add(m.connectionTimeout))

	for scanner.Scan() {
		conn.SetReadDeadline(time.Now().Add(m.connectionTimeout))

		line := scanner.Text()
		if line == "" {
			continue
		}

		var msg socket.Message
		if err := json.Unmarshal([]byte(line), &msg); err != nil {
			m.messageBridge.SendMessage(socket.ErrorMsg(fmt.Sprintf("Failed to parse message: %v", err)))
			continue
		}

		switch msg.Type {
		case "context_update":
			if contextData, ok := msg.ExtractContextData(); ok {
				m.messageBridge.SendMessage(socket.ContextUpdateMsg{Data: contextData})
			} else {
				m.messageBridge.SendMessage(socket.ErrorMsg("Failed to extract context data from message"))
			}

		case "cursor_pos":
			if contextData, ok := msg.ExtractContextData(); ok {
				m.messageBridge.SendMessage(socket.ContextUpdateMsg{Data: contextData})
			}

		case "ping":
			if pingData, ok := msg.ExtractPingData(); ok {
				m.handlePing(conn, pingData.Timestamp)
			} else {
				m.handlePing(conn, msg.Timestamp)
			}

		case "disconnect":
			return

		case "error":
			if errorData, ok := msg.ExtractErrorData(); ok {
				m.messageBridge.SendMessage(socket.ErrorMsg(errorData.Error))
			} else {
				m.messageBridge.SendMessage(socket.ErrorMsg("Unknown error occurred"))
			}

		default:
			m.messageBridge.SendMessage(socket.ErrorMsg(fmt.Sprintf("Unknown message type: %s", msg.Type)))
		}
	}

	if err := scanner.Err(); err != nil {
		m.messageBridge.SendMessage(socket.ErrorMsg(fmt.Sprintf("Connection error: %v", err)))
	}
}

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

	conn.Write(append(data, '\n'))
	m.messageBridge.SendMessage(HeartbeatMsg{Timestamp: time.Now().UnixMilli()})
}

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
