package main

import (
	"encoding/json"
	"testing"
	"time"
)

func TestConfig(t *testing.T) {
	config := getDefaultConfig()
	
	if len(config.Scenarios) == 0 {
		t.Error("Expected default config to have scenarios")
	}
	
	// Test first scenario
	scenario := config.Scenarios[0]
	if scenario.Name == "" {
		t.Error("Expected scenario to have a name")
	}
	
	if scenario.Data.File == "" {
		t.Error("Expected scenario data to have a file")
	}
}

func TestScenarioSerialization(t *testing.T) {
	config := getDefaultConfig()
	scenario := config.Scenarios[0]
	
	// Test JSON serialization
	data, err := json.Marshal(scenario)
	if err != nil {
		t.Fatalf("Failed to marshal scenario: %v", err)
	}
	
	// Test JSON deserialization
	var parsed TestScenario
	err = json.Unmarshal(data, &parsed)
	if err != nil {
		t.Fatalf("Failed to unmarshal scenario: %v", err)
	}
	
	// Verify data
	if parsed.Name != scenario.Name {
		t.Errorf("Name mismatch: got %s, want %s", parsed.Name, scenario.Name)
	}
}

func TestCreateMessage(t *testing.T) {
	data := ContextData{
		File:      "test.go",
		Line:      1,
		Col:       1,
		Timestamp: time.Now().UnixMilli(),
	}
	
	msg := Message{
		Type:      "context_update",
		Timestamp: time.Now().UnixMilli(),
		Data:      data,
	}
	
	// Should be valid JSON
	jsonData, err := json.Marshal(msg)
	if err != nil {
		t.Fatalf("Failed to create JSON message: %v", err)
	}
	
	// Should be parseable
	var parsed Message
	err = json.Unmarshal(jsonData, &parsed)
	if err != nil {
		t.Fatalf("Failed to parse JSON message: %v", err)
	}
	
	if parsed.Type != "context_update" {
		t.Errorf("Wrong message type: got %s, want context_update", parsed.Type)
	}
}
