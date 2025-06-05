package styles

import (
	"github.com/charmbracelet/lipgloss"
	"github.com/star-lance/nvim-hoverfloat/cmd/context-tui/internal/config"
)

// Colors are now loaded from aesthetics.conf - no more hardcoded values!

// Styles contains all styled components
type Styles struct {
	// Layout styles
	Base    lipgloss.Style
	Header  lipgloss.Style
	Footer  lipgloss.Style
	Content lipgloss.Style
	Sidebar lipgloss.Style

	// Content section styles
	Section        lipgloss.Style
	SectionHeader  lipgloss.Style
	SectionContent lipgloss.Style
	SectionFocused lipgloss.Style

	// Interactive styles
	Menu           lipgloss.Style
	MenuItem       lipgloss.Style
	MenuItemActive lipgloss.Style

	// Text styles
	Title     lipgloss.Style
	Subtitle  lipgloss.Style
	Body      lipgloss.Style
	Code      lipgloss.Style
	Comment   lipgloss.Style
	Highlight lipgloss.Style

	// Status styles
	StatusGood    lipgloss.Style
	StatusWarning lipgloss.Style
	StatusError   lipgloss.Style
	StatusInfo    lipgloss.Style

	// Special element styles
	Border     lipgloss.Style
	Keybind    lipgloss.Style
	Path       lipgloss.Style
	LineNumber lipgloss.Style

	// Focus indicators
	FocusedBorder   lipgloss.Style
	UnfocusedBorder lipgloss.Style
}

// New creates a new Styles instance with all styles initialized
func New() *Styles {
	// Ensure config is loaded
	if config.Config == nil {
		config.InitializeAesthetics()
	}
	
	cfg := config.Config
	s := &Styles{}

	// Base styles - using centralized config
	s.Base = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Background.Primary)).
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Primary))

	// Layout styles - using config with consistent full-width backgrounds
	s.Header = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Background.Accent)).
		Foreground(lipgloss.Color(cfg.Colors.Accent.Blue)).
		Bold(cfg.Formatting.Text.BoldHeaders).
		Padding(0, cfg.Layout.Spacing.HeaderPadding).
		Align(lipgloss.Left)

	s.Footer = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Background.Secondary)).
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Comment)).
		Padding(0, cfg.Layout.Spacing.FooterPadding).
		Align(lipgloss.Left)

	s.Content = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Background.Primary)).
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Primary)).
		Padding(cfg.Layout.Spacing.ContentPadding)

	s.Sidebar = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Background.Secondary)).
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Secondary)).
		Padding(1).
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(cfg.Colors.Semantic.BorderDim))

	// Section styles - FIXED: consistent full-width backgrounds
	borderStyle := lipgloss.NormalBorder()
	var borderSides []bool
	switch cfg.Formatting.Sections.BorderStyle {
	case "bottom_only":
		borderSides = []bool{false, false, true, false} // top, right, bottom, left
	case "full":
		borderSides = []bool{true, true, true, true}
	default:
		borderSides = []bool{false, false, true, false}
	}

	s.Section = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Background.Secondary)).
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Primary)).
		MarginBottom(cfg.Layout.Spacing.SectionMarginBottom).
		Padding(cfg.Formatting.Sections.PaddingVertical, cfg.Formatting.Sections.PaddingHorizontal).
		Border(borderStyle, borderSides...).
		BorderForeground(lipgloss.Color(cfg.Colors.Semantic.BorderDim))

	s.SectionFocused = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Background.Selection)).
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Primary)).
		MarginBottom(cfg.Layout.Spacing.SectionMarginBottom).
		Padding(cfg.Formatting.Sections.PaddingVertical, cfg.Formatting.Sections.PaddingHorizontal).
		Border(lipgloss.ThickBorder(), borderSides...).
		BorderForeground(lipgloss.Color(cfg.Colors.Semantic.Focus))

	s.SectionHeader = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Background.Accent)).
		Foreground(lipgloss.Color(cfg.Colors.Accent.Yellow)).
		Bold(cfg.Formatting.Text.BoldHeaders).
		Padding(0, cfg.Formatting.Sections.PaddingHorizontal).
		MarginBottom(1)

	s.SectionContent = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Background.Secondary)).
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Primary)).
		Padding(0, cfg.Formatting.Sections.PaddingHorizontal)

	// Menu styles
	s.Menu = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Background.Floating)).
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Primary)).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color(cfg.Colors.Semantic.Border)).
		Padding(1).
		Width(30)

	s.MenuItem = lipgloss.NewStyle().
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Secondary)).
		Padding(0, 1)

	s.MenuItemActive = s.MenuItem.Copy().
		Background(lipgloss.Color(cfg.Colors.Semantic.Focus)).
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Inverse)).
		Bold(true)

	// Text styles
	s.Title = lipgloss.NewStyle().
		Foreground(lipgloss.Color(cfg.Colors.Accent.Blue)).
		Bold(cfg.Formatting.Text.BoldHeaders).
		MarginBottom(1)

	s.Subtitle = lipgloss.NewStyle().
		Foreground(lipgloss.Color(cfg.Colors.Accent.Purple)).
		Bold(cfg.Formatting.Text.BoldHeaders)

	s.Body = lipgloss.NewStyle().
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Primary))

	s.Code = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Background.CodeBlock)).
		Foreground(lipgloss.Color(cfg.Colors.Accent.Green)).
		Padding(0, 1)

	s.Comment = lipgloss.NewStyle().
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Comment)).
		Italic(cfg.Formatting.Text.ItalicComments)

	s.Highlight = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Accent.Yellow)).
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Inverse)).
		Bold(true)

	// Status styles
	s.StatusGood = lipgloss.NewStyle().
		Foreground(lipgloss.Color(cfg.Colors.Semantic.Success)).
		Bold(true)

	s.StatusWarning = lipgloss.NewStyle().
		Foreground(lipgloss.Color(cfg.Colors.Semantic.Warning)).
		Bold(true)

	s.StatusError = lipgloss.NewStyle().
		Foreground(lipgloss.Color(cfg.Colors.Semantic.Error)).
		Bold(true)

	s.StatusInfo = lipgloss.NewStyle().
		Foreground(lipgloss.Color(cfg.Colors.Semantic.Info)).
		Bold(true)

	// Special element styles
	s.Border = lipgloss.NewStyle().
		Foreground(lipgloss.Color(cfg.Colors.Semantic.Border))

	s.Keybind = lipgloss.NewStyle().
		Background(lipgloss.Color(cfg.Colors.Background.Accent)).
		Foreground(lipgloss.Color(cfg.Colors.Accent.Orange)).
		Bold(true).
		Padding(0, 1)

	s.Path = lipgloss.NewStyle().
		Foreground(lipgloss.Color(cfg.Colors.Accent.Cyan)).
		Underline(cfg.Formatting.Text.UnderlineLinks)

	s.LineNumber = lipgloss.NewStyle().
		Foreground(lipgloss.Color(cfg.Colors.Foreground.Comment)).
		Width(4).
		Align(lipgloss.Right)

	// Focus indicators
	s.FocusedBorder = lipgloss.NewStyle().
		Border(lipgloss.ThickBorder()).
		BorderForeground(lipgloss.Color(cfg.Colors.Semantic.Focus))

	s.UnfocusedBorder = lipgloss.NewStyle().
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(cfg.Colors.Semantic.BorderDim))

	return s
}

// WithWidth returns a copy of the style with the specified width
func (s *Styles) WithWidth(style lipgloss.Style, width int) lipgloss.Style {
	return style.Copy().Width(width)
}

// WithHeight returns a copy of the style with the specified height
func (s *Styles) WithHeight(style lipgloss.Style, height int) lipgloss.Style {
	return style.Copy().Height(height)
}

// WithSize returns a copy of the style with the specified width and height
func (s *Styles) WithSize(style lipgloss.Style, width, height int) lipgloss.Style {
	return style.Copy().Width(width).Height(height)
}

// Focused returns the focused version of a section style
func (s *Styles) Focused(style lipgloss.Style) lipgloss.Style {
	cfg := config.Config
	return style.Copy().
		Border(lipgloss.ThickBorder()).
		BorderForeground(lipgloss.Color(cfg.Colors.Semantic.Focus))
}

// Unfocused returns the unfocused version of a section style
func (s *Styles) Unfocused(style lipgloss.Style) lipgloss.Style {
	cfg := config.Config
	return style.Copy().
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(cfg.Colors.Semantic.BorderDim))
}

// ToggleStatus returns a style based on boolean state
func (s *Styles) ToggleStatus(enabled bool) lipgloss.Style {
	if enabled {
		return s.StatusGood
	}
	return s.StatusError
}

// PriorityColor returns a color based on priority level
func (s *Styles) PriorityColor(level int) lipgloss.Style {
	switch level {
	case 0:
		return s.StatusError // High priority
	case 1:
		return s.StatusWarning // Medium priority
	default:
		return s.StatusInfo // Low priority
	}
}

// FileIcon returns an appropriate icon for the file type
func (s *Styles) FileIcon(filename string) string {
	// Simple file type detection - could be expanded
	switch {
	case len(filename) > 3 && filename[len(filename)-3:] == ".go":
		return "🐹"
	case len(filename) > 3 && filename[len(filename)-3:] == ".rs":
		return "🦀"
	case len(filename) > 3 && filename[len(filename)-3:] == ".py":
		return "🐍"
	case len(filename) > 3 && filename[len(filename)-3:] == ".js":
		return "📜"
	case len(filename) > 3 && filename[len(filename)-3:] == ".ts":
		return "📘"
	case len(filename) > 5 && filename[len(filename)-5:] == ".json":
		return "📋"
	case len(filename) > 4 && filename[len(filename)-4:] == ".lua":
		return "🌙"
	default:
		return "📄"
	}
}

// StatusIcon returns an appropriate status icon
func (s *Styles) StatusIcon(status string) string {
	switch status {
	case "connected":
		return "🔗"
	case "disconnected":
		return "❌"
	case "error":
		return "⚠️"
	case "loading":
		return "⏳"
	default:
		return "ℹ️"
	}
}
