package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
	"time"
)

// ContextData represents the structure sent by the Neovim plugin
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

type LocationInfo struct {
	File string `json:"file"`
	Line int    `json:"line"`
	Col  int    `json:"col"`
}

type Message struct {
	Type      string      `json:"type"`
	Timestamp int64       `json:"timestamp"`
	Data      ContextData `json:"data"`
}

type TestScenario struct {
	Name        string      `json:"name"`
	Description string      `json:"description"`
	Data        ContextData `json:"data"`
	Delay       int         `json:"delay_ms"`
}

type Config struct {
	SocketPath string         `json:"socket_path"`
	Scenarios  []TestScenario `json:"scenarios"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: mock-nvim-client <mode>")
		fmt.Println("Modes:")
		fmt.Println("  interactive  - Send test data with menu for scenario selection")
		fmt.Println("  scenario     - Run specific scenario from scenarios.json")
		fmt.Println("  continuous   - Cycle through all scenarios continuously")
		fmt.Println("  single       - Send one test message and exit")
		os.Exit(1)
	}

	mode := os.Args[1]
	socketPath := "/tmp/nvim_context.sock"

	// Remove existing socket
	os.Remove(socketPath)

	// Load configuration
	config, err := loadConfig("scenarios.json")
	if err != nil {
		log.Printf("Warning: Could not load scenarios.json: %v", err)
		config = getDefaultConfig()
	}
	config.SocketPath = socketPath

	switch mode {
	case "interactive":
		runInteractiveMode(config)
	case "scenario":
		if len(os.Args) < 3 {
			fmt.Println("Usage: mock-nvim-client scenario <scenario_name>")
			listScenarios(config)
			os.Exit(1)
		}
		runScenario(config, os.Args[2])
	case "continuous":
		runContinuousMode(config)
	case "single":
		runSingleTest(config)
	default:
		fmt.Printf("Unknown mode: %s\n", mode)
		os.Exit(1)
	}
}

func loadConfig(filename string) (*Config, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	var config Config
	err = json.Unmarshal(data, &config)
	return &config, err
}

func getDefaultConfig() *Config {
	return &Config{
		Scenarios: []TestScenario{
			{
				Name:        "basic_function",
				Description: "Basic function with type info and references",
				Delay:       500,
				Data: ContextData{
					File:      "src/main.rs",
					Line:      42,
					Col:       15,
					Timestamp: time.Now().UnixMilli(),
					Hover: []string{
						"```rust",
						"fn calculate_distance(p1: Point, p2: Point) -> f64",
						"```",
						"",
						"Calculates the Euclidean distance between two points.",
						"",
						"# Arguments",
						"* `p1` - The first point",
						"* `p2` - The second point",
						"",
						"# Returns",
						"The distance as a floating point number.",
					},
					Definition: &LocationInfo{
						File: "src/geometry.rs",
						Line: 128,
						Col:  4,
					},
					ReferencesCount: 7,
					References: []LocationInfo{
						{File: "src/main.rs", Line: 42, Col: 15},
						{File: "src/tests.rs", Line: 23, Col: 8},
						{File: "src/utils.rs", Line: 156, Col: 20},
						{File: "examples/demo.rs", Line: 89, Col: 12},
					},
					ReferencesMore: 3,
					TypeDefinition: &LocationInfo{
						File: "src/types.rs",
						Line: 45,
						Col:  8,
					},
				},
			},
			{
				Name:        "long_documentation",
				Description: "Function with extensive documentation",
				Delay:       750,
				Data: ContextData{
					File:      "src/complex.rs",
					Line:      156,
					Col:       23,
					Timestamp: time.Now().UnixMilli(),
					Hover: []string{
						"```rust",
						"pub fn advanced_algorithm<T: Clone + Debug>(",
						"    input: &[T],",
						"    predicate: impl Fn(&T) -> bool,",
						"    transform: impl Fn(T) -> T,",
						") -> Result<Vec<T>, ProcessingError>",
						"```",
						"",
						"An advanced algorithm that processes input data with sophisticated filtering",
						"and transformation capabilities. This function is designed to handle complex",
						"data processing scenarios where performance and flexibility are critical.",
						"",
						"# Type Parameters",
						"* `T` - The type of elements in the input slice. Must implement Clone and Debug.",
						"",
						"# Arguments",
						"* `input` - A slice containing the input data to be processed",
						"* `predicate` - A closure that determines which elements should be included",
						"* `transform` - A closure that transforms each selected element",
						"",
						"# Returns",
						"Returns a Result containing either:",
						"* `Ok(Vec<T>)` - A vector of transformed elements that passed the predicate",
						"* `Err(ProcessingError)` - An error if processing failed",
						"",
						"# Examples",
						"```rust",
						"let numbers = vec![1, 2, 3, 4, 5];",
						"let result = advanced_algorithm(",
						"    &numbers,",
						"    |x| *x % 2 == 0,  // Filter even numbers",
						"    |x| x * 2,        // Double them",
						");",
						"assert_eq!(result.unwrap(), vec![4, 8]);",
						"```",
						"",
						"# Panics",
						"This function will panic if the transform closure panics on any element.",
						"",
						"# Performance",
						"The algorithm has O(n) time complexity where n is the length of the input.",
						"Memory usage is proportional to the number of elements that pass the predicate.",
					},
					Definition: &LocationInfo{
						File: "src/algorithms.rs",
						Line: 45,
						Col:  8,
					},
					ReferencesCount: 23,
					References: []LocationInfo{
						{File: "src/main.rs", Line: 78, Col: 12},
						{File: "src/processor.rs", Line: 234, Col: 16},
						{File: "src/data_pipeline.rs", Line: 67, Col: 8},
						{File: "tests/integration.rs", Line: 145, Col: 20},
						{File: "benches/performance.rs", Line: 89, Col: 4},
					},
					ReferencesMore: 18,
				},
			},
			{
				Name:        "no_references",
				Description: "Function with no references (newly defined)",
				Delay:       300,
				Data: ContextData{
					File:      "src/new_feature.rs",
					Line:      12,
					Col:       8,
					Timestamp: time.Now().UnixMilli(),
					Hover: []string{
						"```rust",
						"fn experimental_feature() -> bool",
						"```",
						"",
						"A newly implemented experimental feature.",
						"This function is still under development.",
					},
					Definition: &LocationInfo{
						File: "src/new_feature.rs",
						Line: 12,
						Col:  4,
					},
					ReferencesCount: 0,
					References:      []LocationInfo{},
				},
			},
			{
				Name:        "many_references",
				Description: "Popular utility function with many references",
				Delay:       600,
				Data: ContextData{
					File:      "src/utils.rs",
					Line:      89,
					Col:       12,
					Timestamp: time.Now().UnixMilli(),
					Hover: []string{
						"```rust",
						"pub fn format_error(error: &Error) -> String",
						"```",
						"",
						"Formats an error for display to the user.",
						"Commonly used throughout the application.",
					},
					Definition: &LocationInfo{
						File: "src/utils.rs",
						Line: 89,
						Col:  4,
					},
					ReferencesCount: 156,
					References: []LocationInfo{
						{File: "src/main.rs", Line: 23, Col: 16},
						{File: "src/error_handler.rs", Line: 45, Col: 8},
						{File: "src/cli.rs", Line: 78, Col: 12},
						{File: "src/server.rs", Line: 234, Col: 20},
						{File: "src/client.rs", Line: 156, Col: 8},
						{File: "src/database.rs", Line: 89, Col: 16},
						{File: "src/auth.rs", Line: 67, Col: 12},
						{File: "src/validation.rs", Line: 123, Col: 4},
					},
					ReferencesMore: 148,
				},
			},
		},
	}
}

func sendMessage(socketPath string, data ContextData) error {
	conn, err := net.Dial("unix", socketPath)
	if err != nil {
		return fmt.Errorf("failed to connect to socket: %w", err)
	}
	defer conn.Close()

	message := Message{
		Type:      "context_update",
		Timestamp: time.Now().UnixMilli(),
		Data:      data,
	}

	encoder := json.NewEncoder(conn)
	return encoder.Encode(message)
}

func runInteractiveMode(config *Config) {
	fmt.Println("🔧 Mock Neovim Client - Interactive Mode")
	fmt.Println("========================================")
	fmt.Println("Available scenarios:")

	for i, scenario := range config.Scenarios {
		fmt.Printf("  %d. %s - %s\n", i+1, scenario.Name, scenario.Description)
	}
	fmt.Println("  q. Quit")
	fmt.Println()

	for {
		fmt.Print("Select scenario (1-", len(config.Scenarios), ") or 'q' to quit: ")
		var input string
		fmt.Scanln(&input)

		if input == "q" || input == "quit" {
			break
		}

		var choice int
		if n, err := fmt.Sscanf(input, "%d", &choice); n == 1 && err == nil {
			if choice >= 1 && choice <= len(config.Scenarios) {
				scenario := config.Scenarios[choice-1]
				fmt.Printf("📤 Sending scenario: %s\n", scenario.Name)

				if err := sendMessage(config.SocketPath, scenario.Data); err != nil {
					fmt.Printf("❌ Error: %v\n", err)
				} else {
					fmt.Printf("✅ Sent successfully\n")
				}

				if scenario.Delay > 0 {
					time.Sleep(time.Duration(scenario.Delay) * time.Millisecond)
				}
			} else {
				fmt.Println("❌ Invalid choice")
			}
		} else {
			fmt.Println("❌ Invalid input")
		}
	}
}

func runScenario(config *Config, scenarioName string) {
	for _, scenario := range config.Scenarios {
		if scenario.Name == scenarioName {
			fmt.Printf("📤 Running scenario: %s\n", scenario.Description)
			if err := sendMessage(config.SocketPath, scenario.Data); err != nil {
				log.Fatalf("❌ Error: %v", err)
			}
			fmt.Println("✅ Scenario completed")
			return
		}
	}
	fmt.Printf("❌ Scenario '%s' not found\n", scenarioName)
	listScenarios(config)
}

func runContinuousMode(config *Config) {
	fmt.Println("🔄 Running continuous mode (Ctrl+C to stop)")

	for {
		for _, scenario := range config.Scenarios {
			fmt.Printf("📤 Sending: %s\n", scenario.Name)

			if err := sendMessage(config.SocketPath, scenario.Data); err != nil {
				log.Printf("❌ Error: %v", err)
			} else {
				fmt.Printf("✅ Sent: %s\n", scenario.Name)
			}

			delay := scenario.Delay
			if delay == 0 {
				delay = 2000 // Default 2 second delay
			}
			time.Sleep(time.Duration(delay) * time.Millisecond)
		}
	}
}

func runSingleTest(config *Config) {
	if len(config.Scenarios) == 0 {
		log.Fatal("❌ No scenarios available")
	}

	scenario := config.Scenarios[0]
	fmt.Printf("📤 Sending single test: %s\n", scenario.Description)

	if err := sendMessage(config.SocketPath, scenario.Data); err != nil {
		log.Fatalf("❌ Error: %v", err)
	}

	fmt.Println("✅ Test completed")
}

func listScenarios(config *Config) {
	fmt.Println("Available scenarios:")
	for _, scenario := range config.Scenarios {
		fmt.Printf("  - %s: %s\n", scenario.Name, scenario.Description)
	}
}
