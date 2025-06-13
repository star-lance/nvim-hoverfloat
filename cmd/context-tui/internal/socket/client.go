package socket

import (
	"encoding/json"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// Message represents the JSON message format for persistent connections
type Message struct {
	Type      string      `json:"type"`
	Timestamp int64       `json:"timestamp"`
	Data      interface{} `json:"data"` // Changed from ContextData to interface{}
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

// PingData represents ping message payload
type PingData struct {
	Timestamp int64 `json:"timestamp"`
}

// PongData represents pong message payload
type PongData struct {
	Timestamp       int64 `json:"timestamp"`
	ClientTimestamp int64 `json:"client_timestamp,omitempty"`
}

// ErrorData represents error message payload
type ErrorData struct {
	Error   string `json:"error"`
	Code    int    `json:"code,omitempty"`
	Details string `json:"details,omitempty"`
}

// StatusData represents status message payload
type StatusData struct {
	Status    string                 `json:"status"`
	Message   string                 `json:"message,omitempty"`
	Timestamp int64                  `json:"timestamp"`
	Data      map[string]interface{} `json:"data,omitempty"`
}

// DisconnectData represents disconnect message payload
type DisconnectData struct {
	Reason    string `json:"reason,omitempty"`
	Timestamp int64  `json:"timestamp"`
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
	Data      map[string]interface{}
}

// PingMsg is sent when a ping is received
type PingMsg struct {
	Timestamp int64
}

// PongMsg is sent when a pong is received
type PongMsg struct {
	Timestamp       int64
	ClientTimestamp int64
}

// DisconnectMsg is sent when client requests disconnect
type DisconnectMsg struct {
	Reason string
}

// Bubble Tea command generators

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
func StatusCmd(message string, data map[string]interface{}) tea.Cmd {
	return func() tea.Msg {
		return StatusMsg{
			Message:   message,
			Timestamp: time.Now(),
			Data:      data,
		}
	}
}

// PingCmd returns a command that sends a ping message
func PingCmd(timestamp int64) tea.Cmd {
	return func() tea.Msg {
		return PingMsg{Timestamp: timestamp}
	}
}

// PongCmd returns a command that sends a pong message
func PongCmd(timestamp, clientTimestamp int64) tea.Cmd {
	return func() tea.Msg {
		return PongMsg{
			Timestamp:       timestamp,
			ClientTimestamp: clientTimestamp,
		}
	}
}

// DisconnectCmd returns a command that sends a disconnect message
func DisconnectCmd(reason string) tea.Cmd {
	return func() tea.Msg {
		return DisconnectMsg{Reason: reason}
	}
}

// Message parsing and creation helpers

// ParseMessage parses a JSON message from the socket
func ParseMessage(data []byte) (*Message, error) {
	var msg Message
	err := json.Unmarshal(data, &msg)
	return &msg, err
}

// CreateMessage creates a new message with the specified type and data
func CreateMessage(msgType string, data interface{}) (*Message, error) {
	return &Message{
		Type:      msgType,
		Timestamp: time.Now().UnixMilli(),
		Data:      data,
	}, nil
}

// CreateContextUpdateMessage creates a context update message
func CreateContextUpdateMessage(contextData *ContextData) (*Message, error) {
	return CreateMessage("context_update", contextData)
}

// CreatePingMessage creates a ping message
func CreatePingMessage() (*Message, error) {
	return CreateMessage("ping", PingData{
		Timestamp: time.Now().UnixMilli(),
	})
}

// CreatePongMessage creates a pong message
func CreatePongMessage(clientTimestamp int64) (*Message, error) {
	return CreateMessage("pong", PongData{
		Timestamp:       time.Now().UnixMilli(),
		ClientTimestamp: clientTimestamp,
	})
}

// CreateErrorMessage creates an error message
func CreateErrorMessage(errorMsg string, details string) (*Message, error) {
	return CreateMessage("error", ErrorData{
		Error:   errorMsg,
		Details: details,
	})
}

// CreateDisconnectMessage creates a disconnect message
func CreateDisconnectMessage(reason string) (*Message, error) {
	return CreateMessage("disconnect", DisconnectData{
		Reason:    reason,
		Timestamp: time.Now().UnixMilli(),
	})
}

// Message type constants
const (
	MessageTypeContextUpdate = "context_update"
	MessageTypeCursorPos     = "cursor_pos"     // Fast cursor position updates
	MessageTypePing          = "ping"
	MessageTypePong          = "pong"
	MessageTypeError         = "error"
	MessageTypeStatus        = "status"
	MessageTypeDisconnect    = "disconnect"
)

// IsValidMessageType checks if a message type is valid
func IsValidMessageType(msgType string) bool {
	switch msgType {
	case MessageTypeContextUpdate,
		MessageTypeCursorPos,
		MessageTypePing,
		MessageTypePong,
		MessageTypeError,
		MessageTypeStatus,
		MessageTypeDisconnect:
		return true
	default:
		return false
	}
}

// Helper functions to extract typed data from messages

// ExtractContextData safely extracts ContextData from a message
func (m *Message) ExtractContextData() (*ContextData, bool) {
	if m.Type != MessageTypeContextUpdate {
		return nil, false
	}

	// Try direct type assertion first
	if contextData, ok := m.Data.(*ContextData); ok {
		return contextData, true
	}

	// Try map conversion for JSON unmarshaled data
	if dataMap, ok := m.Data.(map[string]interface{}); ok {
		// Re-marshal and unmarshal to convert to ContextData
		jsonBytes, err := json.Marshal(dataMap)
		if err != nil {
			return nil, false
		}

		var contextData ContextData
		err = json.Unmarshal(jsonBytes, &contextData)
		if err != nil {
			return nil, false
		}

		return &contextData, true
	}

	return nil, false
}

// ExtractErrorData safely extracts ErrorData from a message
func (m *Message) ExtractErrorData() (*ErrorData, bool) {
	if m.Type != MessageTypeError {
		return nil, false
	}

	// Try direct type assertion first
	if errorData, ok := m.Data.(*ErrorData); ok {
		return errorData, true
	}

	// Try map conversion for JSON unmarshaled data
	if dataMap, ok := m.Data.(map[string]interface{}); ok {
		// Re-marshal and unmarshal to convert to ErrorData
		jsonBytes, err := json.Marshal(dataMap)
		if err != nil {
			return nil, false
		}

		var errorData ErrorData
		err = json.Unmarshal(jsonBytes, &errorData)
		if err != nil {
			return nil, false
		}

		return &errorData, true
	}

	return nil, false
}

// ExtractPingData safely extracts PingData from a message
func (m *Message) ExtractPingData() (*PingData, bool) {
	if m.Type != MessageTypePing {
		return nil, false
	}

	// Try direct type assertion first
	if pingData, ok := m.Data.(*PingData); ok {
		return pingData, true
	}

	// Try map conversion for JSON unmarshaled data
	if dataMap, ok := m.Data.(map[string]interface{}); ok {
		// Re-marshal and unmarshal to convert to PingData
		jsonBytes, err := json.Marshal(dataMap)
		if err != nil {
			return nil, false
		}

		var pingData PingData
		err = json.Unmarshal(jsonBytes, &pingData)
		if err != nil {
			return nil, false
		}

		return &pingData, true
	}

	return nil, false
}

// ExtractDisconnectData safely extracts DisconnectData from a message
func (m *Message) ExtractDisconnectData() (*DisconnectData, bool) {
	if m.Type != MessageTypeDisconnect {
		return nil, false
	}

	// Try direct type assertion first
	if disconnectData, ok := m.Data.(*DisconnectData); ok {
		return disconnectData, true
	}

	// Try map conversion for JSON unmarshaled data
	if dataMap, ok := m.Data.(map[string]interface{}); ok {
		// Re-marshal and unmarshal to convert to DisconnectData
		jsonBytes, err := json.Marshal(dataMap)
		if err != nil {
			return nil, false
		}

		var disconnectData DisconnectData
		err = json.Unmarshal(jsonBytes, &disconnectData)
		if err != nil {
			return nil, false
		}

		return &disconnectData, true
	}

	return nil, false
}

// Utility methods for ContextData

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

// IsEmpty returns true if the context data has no useful information
func (c *ContextData) IsEmpty() bool {
	if c == nil {
		return true
	}

	return !c.HasHover() &&
		!c.HasDefinition() &&
		!c.HasReferences() &&
		!c.HasTypeDefinition()
}

// Clone creates a deep copy of the context data
func (c *ContextData) Clone() *ContextData {
	if c == nil {
		return nil
	}

	clone := &ContextData{
		File:            c.File,
		Line:            c.Line,
		Col:             c.Col,
		Timestamp:       c.Timestamp,
		ReferencesCount: c.ReferencesCount,
		ReferencesMore:  c.ReferencesMore,
	}

	// Clone hover data
	if c.Hover != nil {
		clone.Hover = make([]string, len(c.Hover))
		copy(clone.Hover, c.Hover)
	}

	// Clone definition
	if c.Definition != nil {
		clone.Definition = &LocationInfo{
			File: c.Definition.File,
			Line: c.Definition.Line,
			Col:  c.Definition.Col,
		}
	}

	// Clone references
	if c.References != nil {
		clone.References = make([]LocationInfo, len(c.References))
		copy(clone.References, c.References)
	}

	// Clone type definition
	if c.TypeDefinition != nil {
		clone.TypeDefinition = &LocationInfo{
			File: c.TypeDefinition.File,
			Line: c.TypeDefinition.Line,
			Col:  c.TypeDefinition.Col,
		}
	}

	return clone
}

// Utility methods for LocationInfo

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

// IsValid returns true if the location has valid data
func (l *LocationInfo) IsValid() bool {
	return l != nil && l.File != "" && l.Line > 0 && l.Col > 0
}

// Equals compares two location infos for equality
func (l *LocationInfo) Equals(other *LocationInfo) bool {
	if l == nil && other == nil {
		return true
	}
	if l == nil || other == nil {
		return false
	}
	return l.File == other.File && l.Line == other.Line && l.Col == other.Col
}
