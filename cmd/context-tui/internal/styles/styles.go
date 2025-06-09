package styles

import (
	"github.com/charmbracelet/lipgloss"
)

// Tokyo Night color scheme (hardcoded for simplicity)
const (
	// Background colors
	bgPrimary   = "#1a1b26"
	bgSecondary = "#24283b"
	bgAccent    = "#414868"
	bgFloating  = "#16161e"
	bgCodeBlock = "#1f2335"
	bgSelection = "#283457"

	// Foreground colors
	fgPrimary   = "#c0caf5"
	fgSecondary = "#a9b1d6"
	fgComment   = "#565f89"
	fgDark      = "#545c7e"
	fgInverse   = "#1a1b26"

	// Accent colors
	colorBlue   = "#7aa2f7"
	colorGreen  = "#9ece6a"
	colorYellow = "#e0af68"
	colorPurple = "#bb9af7"
	colorRed    = "#f7768e"
	colorOrange = "#ff9e64"
	colorCyan   = "#7dcfff"

	// Semantic colors
	colorBorder    = "#27a1b9"
	colorBorderDim = "#414868"
	colorFocus     = "#7aa2f7"
	colorError     = "#f7768e"
	colorWarning   = "#e0af68"
	colorSuccess   = "#9ece6a"
	colorInfo      = "#7aa2f7"
)

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
	s := &Styles{}

	// Base styles
	s.Base = lipgloss.NewStyle().
		Background(lipgloss.Color(bgPrimary)).
		Foreground(lipgloss.Color(fgPrimary))

	// Layout styles
	s.Header = lipgloss.NewStyle().
		Background(lipgloss.Color(bgAccent)).
		Foreground(lipgloss.Color(colorBlue)).
		Bold(true).
		Padding(0, 2).
		Align(lipgloss.Left)

	s.Footer = lipgloss.NewStyle().
		Background(lipgloss.Color(bgSecondary)).
		Foreground(lipgloss.Color(fgComment)).
		Padding(0, 2).
		Align(lipgloss.Left)

	s.Content = lipgloss.NewStyle().
		Background(lipgloss.Color(bgPrimary)).
		Foreground(lipgloss.Color(fgPrimary)).
		Padding(0)

	s.Sidebar = lipgloss.NewStyle().
		Background(lipgloss.Color(bgSecondary)).
		Foreground(lipgloss.Color(fgSecondary)).
		Padding(1).
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(colorBorderDim))

	// Section styles
	s.Section = lipgloss.NewStyle().
		Background(lipgloss.Color(bgSecondary)).
		Foreground(lipgloss.Color(fgPrimary)).
		MarginBottom(1).
		Padding(1, 2).
		Border(lipgloss.NormalBorder(), false, false, true, false).
		BorderForeground(lipgloss.Color(colorBorderDim))

	s.SectionFocused = lipgloss.NewStyle().
		Background(lipgloss.Color(bgSelection)).
		Foreground(lipgloss.Color(fgPrimary)).
		MarginBottom(1).
		Padding(1, 2).
		Border(lipgloss.ThickBorder(), false, false, true, false).
		BorderForeground(lipgloss.Color(colorFocus))

	s.SectionHeader = lipgloss.NewStyle().
		Background(lipgloss.Color(bgAccent)).
		Foreground(lipgloss.Color(colorYellow)).
		Bold(true).
		Padding(0, 2).
		MarginBottom(1)

	s.SectionContent = lipgloss.NewStyle().
		Background(lipgloss.Color(bgSecondary)).
		Foreground(lipgloss.Color(fgPrimary)).
		Padding(0, 2)

	// Menu styles
	s.Menu = lipgloss.NewStyle().
		Background(lipgloss.Color(bgFloating)).
		Foreground(lipgloss.Color(fgPrimary)).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color(colorBorder)).
		Padding(1).
		Width(30)

	s.MenuItem = lipgloss.NewStyle().
		Foreground(lipgloss.Color(fgSecondary)).
		Padding(0, 1)

	s.MenuItemActive = s.MenuItem.Copy().
		Background(lipgloss.Color(colorFocus)).
		Foreground(lipgloss.Color(fgInverse)).
		Bold(true)

	// Text styles
	s.Title = lipgloss.NewStyle().
		Foreground(lipgloss.Color(colorBlue)).
		Bold(true).
		MarginBottom(1)

	s.Subtitle = lipgloss.NewStyle().
		Foreground(lipgloss.Color(colorPurple)).
		Bold(true)

	s.Body = lipgloss.NewStyle().
		Foreground(lipgloss.Color(fgPrimary))

	s.Code = lipgloss.NewStyle().
		Background(lipgloss.Color(bgCodeBlock)).
		Foreground(lipgloss.Color(colorGreen)).
		Padding(0, 1)

	s.Comment = lipgloss.NewStyle().
		Foreground(lipgloss.Color(fgComment)).
		Italic(true)

	s.Highlight = lipgloss.NewStyle().
		Background(lipgloss.Color(colorYellow)).
		Foreground(lipgloss.Color(fgInverse)).
		Bold(true)

	// Status styles
	s.StatusGood = lipgloss.NewStyle().
		Foreground(lipgloss.Color(colorSuccess)).
		Bold(true)

	s.StatusWarning = lipgloss.NewStyle().
		Foreground(lipgloss.Color(colorWarning)).
		Bold(true)

	s.StatusError = lipgloss.NewStyle().
		Foreground(lipgloss.Color(colorError)).
		Bold(true)

	s.StatusInfo = lipgloss.NewStyle().
		Foreground(lipgloss.Color(colorInfo)).
		Bold(true)

	// Special element styles
	s.Border = lipgloss.NewStyle().
		Foreground(lipgloss.Color(colorBorder))

	s.Keybind = lipgloss.NewStyle().
		Background(lipgloss.Color(bgAccent)).
		Foreground(lipgloss.Color(colorOrange)).
		Bold(true).
		Padding(0, 1)

	s.Path = lipgloss.NewStyle().
		Foreground(lipgloss.Color(colorCyan)).
		Underline(true)

	s.LineNumber = lipgloss.NewStyle().
		Foreground(lipgloss.Color(fgComment)).
		Width(4).
		Align(lipgloss.Right)

	// Focus indicators
	s.FocusedBorder = lipgloss.NewStyle().
		Border(lipgloss.ThickBorder()).
		BorderForeground(lipgloss.Color(colorFocus))

	s.UnfocusedBorder = lipgloss.NewStyle().
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(colorBorderDim))

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
	return style.Copy().
		Border(lipgloss.ThickBorder()).
		BorderForeground(lipgloss.Color(colorFocus))
}

// Unfocused returns the unfocused version of a section style
func (s *Styles) Unfocused(style lipgloss.Style) lipgloss.Style {
	return style.Copy().
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(colorBorderDim))
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
	// Simple file type detection
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