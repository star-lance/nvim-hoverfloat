package socket

import (
	"encoding/json"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// Message represents the JSON message format from Neovim
type Message struct {
	Type      string      `json:"type"`
	Timestamp int64       `json:"timestamp"`
	Data      ContextData `json:"data"`
}

// ContextData represents the LSP context data
type ContextData struct {
	File            string         `json:"file"`
	Line            int            `json:"line"`
	Col             int            `json:"col"`
	Timestamp       int64          `json:"timestamp"`
	Hover           []string       `json:"hover,omitempty"`
	Definition      *LocationInfo  `json:"definition,omitempty"`
	ReferencesCount int            `json:"references_count,omitempty"`
	References      []LocationInfo `json:"references,omitempty"`
	ReferencesMore  int            `json:"references_more,omitempty"`
	TypeDefinition  *LocationInfo  `json:"type_definition,omitempty"`
}

// LocationInfo represents a file location
type LocationInfo struct {
	File string `json:"file"`
	Line int    `json:"line"`
	Col  int    `json:"col"`
}

// Bubble Tea messages for communication with the main model

// ContextUpdateMsg is sent when new context data is received
type ContextUpdateMsg struct {
	Data *ContextData
}

// ErrorMsg is sent when an error occurs
type ErrorMsg string

// ConnectionMsg is sent when connection status changes
type ConnectionMsg bool

// StatusMsg is sent for general status updates
type StatusMsg struct {
	Message   string
	Timestamp time.Time
}

// SocketConnectedCmd returns a command that sends a connection status message
func SocketConnectedCmd(connected bool) tea.Cmd {
	return func() tea.Msg {
		return ConnectionMsg(connected)
	}
}

// ContextUpdateCmd returns a command that sends a context update message
func ContextUpdateCmd(data *ContextData) tea.Cmd {
	return func() tea.Msg {
		return ContextUpdateMsg{Data: data}
	}
}

// ErrorCmd returns a command that sends an error message
func ErrorCmd(err error) tea.Cmd {
	return func() tea.Msg {
		return ErrorMsg(err.Error())
	}
}

// StatusCmd returns a command that sends a status message
func StatusCmd(message string) tea.Cmd {
	return func() tea.Msg {
		return StatusMsg{
			Message:   message,
			Timestamp: time.Now(),
		}
	}
}

// ParseMessage parses a JSON message from the socket
func ParseMessage(data []byte) (*Message, error) {
	var msg Message
	err := json.Unmarshal(data, &msg)
	return &msg, err
}

// FormatContextUpdate formats context data for display
func (c *ContextData) FormatContextUpdate() string {
	if c == nil {
		return "No context data available"
	}

	timestamp := time.UnixMilli(c.Timestamp)
	return "Updated " + timestamp.Format("15:04:05")
}

// HasHover returns true if hover data is available
func (c *ContextData) HasHover() bool {
	return c != nil && len(c.Hover) > 0
}

// HasDefinition returns true if definition data is available
func (c *ContextData) HasDefinition() bool {
	return c != nil && c.Definition != nil
}

// HasReferences returns true if references data is available
func (c *ContextData) HasReferences() bool {
	return c != nil && len(c.References) > 0
}

// HasTypeDefinition returns true if type definition data is available
func (c *ContextData) HasTypeDefinition() bool {
	return c != nil && c.TypeDefinition != nil
}

// GetTotalReferences returns the total number of references
func (c *ContextData) GetTotalReferences() int {
	if c == nil {
		return 0
	}
	return c.ReferencesCount
}

// GetDisplayableReferences returns references that can be displayed
func (c *ContextData) GetDisplayableReferences() []LocationInfo {
	if c == nil || len(c.References) == 0 {
		return []LocationInfo{}
	}
	return c.References
}

// GetMoreReferencesCount returns the number of additional references not displayed
func (c *ContextData) GetMoreReferencesCount() int {
	if c == nil {
		return 0
	}
	return c.ReferencesMore
}

// FormatLocation formats a location for display
func (l *LocationInfo) FormatLocation() string {
	if l == nil {
		return "Unknown location"
	}
	return l.File + ":" + string(rune(l.Line)) + ":" + string(rune(l.Col))
}

// GetShortPath returns a shortened version of the file path
func (l *LocationInfo) GetShortPath(maxLength int) string {
	if l == nil || l.File == "" {
		return "Unknown"
	}

	if len(l.File) <= maxLength {
		return l.File
	}

	// Show ".../" + last part
	return ".../" + l.File[len(l.File)-maxLength+4:]
}
