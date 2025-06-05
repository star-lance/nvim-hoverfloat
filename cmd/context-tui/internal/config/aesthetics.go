package config

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// AestheticsConfig holds all styling configuration
type AestheticsConfig struct {
	Colors     ColorConfig     `json:"colors"`
	Formatting FormattingConfig `json:"formatting"`
	Layout     LayoutConfig     `json:"layout"`
	Markdown   MarkdownConfig   `json:"markdown"`
	Debug      DebugConfig      `json:"debug"`
}

type ColorConfig struct {
	Background BackgroundColors `json:"background"`
	Foreground ForegroundColors `json:"foreground"`
	Accent     AccentColors     `json:"accent"`
	Semantic   SemanticColors   `json:"semantic"`
}

type BackgroundColors struct {
	Primary    string `json:"primary"`
	Secondary  string `json:"secondary"`
	Accent     string `json:"accent"`
	Floating   string `json:"floating"`
	CodeBlock  string `json:"code_block"`
	Selection  string `json:"selection"`
}

type ForegroundColors struct {
	Primary   string `json:"primary"`
	Secondary string `json:"secondary"`
	Comment   string `json:"comment"`
	Dark      string `json:"dark"`
	Inverse   string `json:"inverse"`
}

type AccentColors struct {
	Blue   string `json:"blue"`
	Green  string `json:"green"`
	Yellow string `json:"yellow"`
	Purple string `json:"purple"`
	Red    string `json:"red"`
	Orange string `json:"orange"`
	Cyan   string `json:"cyan"`
	Pink   string `json:"pink"`
}

type SemanticColors struct {
	Border    string `json:"border"`
	BorderDim string `json:"border_dim"`
	Focus     string `json:"focus"`
	Error     string `json:"error"`
	Warning   string `json:"warning"`
	Success   string `json:"success"`
	Info      string `json:"info"`
}

type FormattingConfig struct {
	Text     TextFormatting     `json:"text"`
	Sections SectionFormatting  `json:"sections"`
	Code     CodeFormatting     `json:"code"`
}

type TextFormatting struct {
	BoldHeaders     bool `json:"bold_headers"`
	ItalicComments  bool `json:"italic_comments"`
	UnderlineLinks  bool `json:"underline_links"`
	ItalicEmphasis  bool `json:"italic_emphasis"`
}

type SectionFormatting struct {
	ConsistentBackgrounds bool   `json:"consistent_backgrounds"`
	FullWidthBackgrounds  bool   `json:"full_width_backgrounds"`
	UniformPadding        bool   `json:"uniform_padding"`
	BorderStyle          string `json:"border_style"`
	PaddingHorizontal    int    `json:"padding_horizontal"`
	PaddingVertical      int    `json:"padding_vertical"`
}

type CodeFormatting struct {
	HighlightSyntax      bool `json:"highlight_syntax"`
	PreserveIndentation  bool `json:"preserve_indentation"`
	BackgroundConsistent bool `json:"background_consistent"`
	BorderCodeBlocks     bool `json:"border_code_blocks"`
}

type LayoutConfig struct {
	Spacing    SpacingConfig    `json:"spacing"`
	Dimensions DimensionsConfig `json:"dimensions"`
}

type SpacingConfig struct {
	SectionMarginBottom int `json:"section_margin_bottom"`
	HeaderPadding       int `json:"header_padding"`
	FooterPadding       int `json:"footer_padding"`
	ContentPadding      int `json:"content_padding"`
}

type DimensionsConfig struct {
	MinWidth      int `json:"min_width"`
	MaxWidth      int `json:"max_width"`
	DefaultHeight int `json:"default_height"`
}

type MarkdownConfig struct {
	UseGlamour         bool `json:"use_glamour"`
	Theme             string `json:"theme"`
	CodeHighlighting  bool `json:"code_highlighting"`
	PreserveFormatting bool `json:"preserve_formatting"`
	WordWrap          bool `json:"word_wrap"`
}

type DebugConfig struct {
	ShowBoundaries       bool `json:"show_boundaries"`
	LogColorUsage        bool `json:"log_color_usage"`
	ValidateConsistency  bool `json:"validate_consistency"`
}

// Global configuration instance
var Config *AestheticsConfig

// LoadAestheticsConfig loads configuration from aesthetics.conf
func LoadAestheticsConfig(configPath string) (*AestheticsConfig, error) {
	if configPath == "" {
		// Default path relative to project root
		configPath = "config/aesthetics.conf"
	}
	
	// Try to find the config file
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		// Try relative to executable
		execPath, _ := os.Executable()
		execDir := filepath.Dir(execPath)
		configPath = filepath.Join(execDir, "..", "..", "config", "aesthetics.conf")
		
		if _, err := os.Stat(configPath); os.IsNotExist(err) {
			return nil, fmt.Errorf("aesthetics.conf not found")
		}
	}

	config := &AestheticsConfig{}
	
	file, err := os.Open(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open config file: %v", err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	currentSection := ""
	currentSubsection := ""

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		
		// Skip empty lines and comments
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		
		// Section headers
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section := strings.Trim(line, "[]")
			parts := strings.Split(section, ".")
			currentSection = parts[0]
			if len(parts) > 1 {
				currentSubsection = parts[1]
			} else {
				currentSubsection = ""
			}
			continue
		}
		
		// Key-value pairs
		if strings.Contains(line, "=") {
			parts := strings.SplitN(line, "=", 2)
			key := strings.TrimSpace(parts[0])
			value := strings.TrimSpace(parts[1])
			
			// Remove quotes if present
			value = strings.Trim(value, "\"")
			
			err := setConfigValue(config, currentSection, currentSubsection, key, value)
			if err != nil {
				return nil, fmt.Errorf("error setting config value %s.%s.%s: %v", currentSection, currentSubsection, key, err)
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading config file: %v", err)
	}

	// Set global config
	Config = config
	
	return config, nil
}

// setConfigValue sets a configuration value based on section, subsection, and key
func setConfigValue(config *AestheticsConfig, section, subsection, key, value string) error {
	switch section {
	case "colors":
		return setColorValue(config, subsection, key, value)
	case "formatting":
		return setFormattingValue(config, subsection, key, value)
	case "layout":
		return setLayoutValue(config, subsection, key, value)
	case "markdown":
		return setMarkdownValue(config, key, value)
	case "debug":
		return setDebugValue(config, key, value)
	default:
		return fmt.Errorf("unknown section: %s", section)
	}
}

func setColorValue(config *AestheticsConfig, subsection, key, value string) error {
	switch subsection {
	case "background":
		switch key {
		case "primary":
			config.Colors.Background.Primary = value
		case "secondary":
			config.Colors.Background.Secondary = value
		case "accent":
			config.Colors.Background.Accent = value
		case "floating":
			config.Colors.Background.Floating = value
		case "code_block":
			config.Colors.Background.CodeBlock = value
		case "selection":
			config.Colors.Background.Selection = value
		default:
			return fmt.Errorf("unknown background color: %s", key)
		}
	case "foreground":
		switch key {
		case "primary":
			config.Colors.Foreground.Primary = value
		case "secondary":
			config.Colors.Foreground.Secondary = value
		case "comment":
			config.Colors.Foreground.Comment = value
		case "dark":
			config.Colors.Foreground.Dark = value
		case "inverse":
			config.Colors.Foreground.Inverse = value
		default:
			return fmt.Errorf("unknown foreground color: %s", key)
		}
	case "accent":
		switch key {
		case "blue":
			config.Colors.Accent.Blue = value
		case "green":
			config.Colors.Accent.Green = value
		case "yellow":
			config.Colors.Accent.Yellow = value
		case "purple":
			config.Colors.Accent.Purple = value
		case "red":
			config.Colors.Accent.Red = value
		case "orange":
			config.Colors.Accent.Orange = value
		case "cyan":
			config.Colors.Accent.Cyan = value
		case "pink":
			config.Colors.Accent.Pink = value
		default:
			return fmt.Errorf("unknown accent color: %s", key)
		}
	case "semantic":
		switch key {
		case "border":
			config.Colors.Semantic.Border = value
		case "border_dim":
			config.Colors.Semantic.BorderDim = value
		case "focus":
			config.Colors.Semantic.Focus = value
		case "error":
			config.Colors.Semantic.Error = value
		case "warning":
			config.Colors.Semantic.Warning = value
		case "success":
			config.Colors.Semantic.Success = value
		case "info":
			config.Colors.Semantic.Info = value
		default:
			return fmt.Errorf("unknown semantic color: %s", key)
		}
	default:
		return fmt.Errorf("unknown color subsection: %s", subsection)
	}
	return nil
}

func setFormattingValue(config *AestheticsConfig, subsection, key, value string) error {
	boolVal, _ := strconv.ParseBool(value)
	intVal, _ := strconv.Atoi(value)
	
	switch subsection {
	case "text":
		switch key {
		case "bold_headers":
			config.Formatting.Text.BoldHeaders = boolVal
		case "italic_comments":
			config.Formatting.Text.ItalicComments = boolVal
		case "underline_links":
			config.Formatting.Text.UnderlineLinks = boolVal
		case "italic_emphasis":
			config.Formatting.Text.ItalicEmphasis = boolVal
		default:
			return fmt.Errorf("unknown text formatting: %s", key)
		}
	case "sections":
		switch key {
		case "consistent_backgrounds":
			config.Formatting.Sections.ConsistentBackgrounds = boolVal
		case "full_width_backgrounds":
			config.Formatting.Sections.FullWidthBackgrounds = boolVal
		case "uniform_padding":
			config.Formatting.Sections.UniformPadding = boolVal
		case "border_style":
			config.Formatting.Sections.BorderStyle = value
		case "padding_horizontal":
			config.Formatting.Sections.PaddingHorizontal = intVal
		case "padding_vertical":
			config.Formatting.Sections.PaddingVertical = intVal
		default:
			return fmt.Errorf("unknown section formatting: %s", key)
		}
	case "code":
		switch key {
		case "highlight_syntax":
			config.Formatting.Code.HighlightSyntax = boolVal
		case "preserve_indentation":
			config.Formatting.Code.PreserveIndentation = boolVal
		case "background_consistent":
			config.Formatting.Code.BackgroundConsistent = boolVal
		case "border_code_blocks":
			config.Formatting.Code.BorderCodeBlocks = boolVal
		default:
			return fmt.Errorf("unknown code formatting: %s", key)
		}
	default:
		return fmt.Errorf("unknown formatting subsection: %s", subsection)
	}
	return nil
}

func setLayoutValue(config *AestheticsConfig, subsection, key, value string) error {
	intVal, _ := strconv.Atoi(value)
	
	switch subsection {
	case "spacing":
		switch key {
		case "section_margin_bottom":
			config.Layout.Spacing.SectionMarginBottom = intVal
		case "header_padding":
			config.Layout.Spacing.HeaderPadding = intVal
		case "footer_padding":
			config.Layout.Spacing.FooterPadding = intVal
		case "content_padding":
			config.Layout.Spacing.ContentPadding = intVal
		default:
			return fmt.Errorf("unknown spacing config: %s", key)
		}
	case "dimensions":
		switch key {
		case "min_width":
			config.Layout.Dimensions.MinWidth = intVal
		case "max_width":
			config.Layout.Dimensions.MaxWidth = intVal
		case "default_height":
			config.Layout.Dimensions.DefaultHeight = intVal
		default:
			return fmt.Errorf("unknown dimensions config: %s", key)
		}
	default:
		return fmt.Errorf("unknown layout subsection: %s", subsection)
	}
	return nil
}

func setMarkdownValue(config *AestheticsConfig, key, value string) error {
	boolVal, _ := strconv.ParseBool(value)
	
	switch key {
	case "use_glamour":
		config.Markdown.UseGlamour = boolVal
	case "theme":
		config.Markdown.Theme = value
	case "code_highlighting":
		config.Markdown.CodeHighlighting = boolVal
	case "preserve_formatting":
		config.Markdown.PreserveFormatting = boolVal
	case "word_wrap":
		config.Markdown.WordWrap = boolVal
	default:
		return fmt.Errorf("unknown markdown config: %s", key)
	}
	return nil
}

func setDebugValue(config *AestheticsConfig, key, value string) error {
	boolVal, _ := strconv.ParseBool(value)
	
	switch key {
	case "show_boundaries":
		config.Debug.ShowBoundaries = boolVal
	case "log_color_usage":
		config.Debug.LogColorUsage = boolVal
	case "validate_consistency":
		config.Debug.ValidateConsistency = boolVal
	default:
		return fmt.Errorf("unknown debug config: %s", key)
	}
	return nil
}

// InitializeAesthetics loads the aesthetics configuration
func InitializeAesthetics() error {
	_, err := LoadAestheticsConfig("")
	return err
}