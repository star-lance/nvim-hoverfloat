package socket

import (
	"encoding/json"
	"testing"
	"time"
)

func TestMessage(t *testing.T) {
	// Test message creation and parsing
	data := &ContextData{
		File:      "test.go",
		Line:      42,
		Col:       15,
		Timestamp: time.Now().UnixMilli(),
		Hover:     []string{"test hover"},
	}
	
	msg := Message{
		Type:      "context_update",
		Timestamp: time.Now().UnixMilli(),
		Data:      *data,
	}
	
	// Test JSON marshaling
	jsonData, err := json.Marshal(msg)
	if err != nil {
		t.Fatalf("Failed to marshal message: %v", err)
	}
	
	// Test JSON unmarshaling
	var parsed Message
	err = json.Unmarshal(jsonData, &parsed)
	if err != nil {
		t.Fatalf("Failed to unmarshal message: %v", err)
	}
	
	// Verify data
	if parsed.Type != msg.Type {
		t.Errorf("Type mismatch: got %s, want %s", parsed.Type, msg.Type)
	}
	
	if parsed.Data.File != data.File {
		t.Errorf("File mismatch: got %s, want %s", parsed.Data.File, data.File)
	}
	
	if parsed.Data.Line != data.Line {
		t.Errorf("Line mismatch: got %d, want %d", parsed.Data.Line, data.Line)
	}
}

func TestContextData(t *testing.T) {
	data := &ContextData{
		File:            "example.rs",
		Line:            100,
		Col:             20,
		Hover:           []string{"fn example() -> bool"},
		ReferencesCount: 5,
		References: []LocationInfo{
			{File: "main.rs", Line: 10, Col: 5},
			{File: "lib.rs", Line: 25, Col: 8},
		},
	}
	
	// Test helper methods
	if !data.HasHover() {
		t.Error("Expected HasHover to return true")
	}
	
	if !data.HasReferences() {
		t.Error("Expected HasReferences to return true")
	}
	
	if data.HasDefinition() {
		t.Error("Expected HasDefinition to return false")
	}
	
	totalRefs := data.GetTotalReferences()
	if totalRefs != 5 {
		t.Errorf("Expected 5 total references, got %d", totalRefs)
	}
	
	displayRefs := data.GetDisplayableReferences()
	if len(displayRefs) != 2 {
		t.Errorf("Expected 2 displayable references, got %d", len(displayRefs))
	}
}

func TestLocationInfo(t *testing.T) {
	loc := &LocationInfo{
		File: "/very/long/path/to/some/file/that/exceeds/normal/length.go",
		Line: 123,
		Col:  45,
	}
	
	// Test path shortening
	shortPath := loc.GetShortPath(20)
	if len(shortPath) > 20 {
		t.Errorf("Shortened path too long: %s (length: %d)", shortPath, len(shortPath))
	}
	
	// Should contain "..."
	if shortPath[:4] != ".../" {
		t.Errorf("Expected shortened path to start with '.../', got: %s", shortPath)
	}
}
