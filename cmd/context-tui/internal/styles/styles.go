package styles

import (
	"github.com/charmbracelet/lipgloss"
)

// TokyoNight color palette to match Neovim theme
const (
	// Background colors
	BgPrimary   = "#1a1b26"
	BgSecondary = "#24283b"
	BgAccent    = "#414868"
	BgFloat     = "#16161e"

	// Foreground colors
	FgPrimary   = "#c0caf5"
	FgSecondary = "#a9b1d6"
	FgComment   = "#565f89"
	FgDark      = "#545c7e"

	// Accent colors
	Blue   = "#7aa2f7"
	Green  = "#9ece6a"
	Yellow = "#e0af68"
	Purple = "#bb9af7"
	Red    = "#f7768e"
	Orange = "#ff9e64"
	Cyan   = "#7dcfff"
	Pink   = "#ff007c"

	// Special colors
	Border    = "#27a1b9"
	BorderDim = "#414868"
	Focus     = "#7aa2f7"
	Error     = "#f7768e"
	Warning   = "#e0af68"
	Success   = "#9ece6a"
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
		Background(lipgloss.Color(BgPrimary)).
		Foreground(lipgloss.Color(FgPrimary))

	// Layout styles - properly fill terminal width
	s.Header = lipgloss.NewStyle().
		Background(lipgloss.Color(BgAccent)).
		Foreground(lipgloss.Color(Blue)).
		Bold(true).
		Padding(0, 2).
		Align(lipgloss.Left)

	s.Footer = lipgloss.NewStyle().
		Background(lipgloss.Color(BgSecondary)).
		Foreground(lipgloss.Color(FgComment)).
		Padding(0, 2).
		Align(lipgloss.Left)

	s.Content = lipgloss.NewStyle().
		Background(lipgloss.Color(BgPrimary)).
		Foreground(lipgloss.Color(FgPrimary)).
		Padding(0)

	s.Sidebar = lipgloss.NewStyle().
		Background(lipgloss.Color(BgSecondary)).
		Foreground(lipgloss.Color(FgSecondary)).
		Padding(1).
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(BorderDim))

	// Section styles - full width with proper backgrounds
	s.Section = lipgloss.NewStyle().
		Background(lipgloss.Color(BgSecondary)).
		Foreground(lipgloss.Color(FgPrimary)).
		MarginBottom(1).
		Padding(1, 2).
		Border(lipgloss.NormalBorder(), false, false, true, false).
		BorderForeground(lipgloss.Color(BorderDim))

	s.SectionFocused = lipgloss.NewStyle().
		Background(lipgloss.Color(BgAccent)).
		Foreground(lipgloss.Color(FgPrimary)).
		MarginBottom(1).
		Padding(1, 2).
		Border(lipgloss.ThickBorder(), false, false, true, false).
		BorderForeground(lipgloss.Color(Focus))

	s.SectionHeader = lipgloss.NewStyle().
		Background(lipgloss.Color(BgAccent)).
		Foreground(lipgloss.Color(Yellow)).
		Bold(true).
		Padding(0, 2).
		MarginBottom(1)

	s.SectionContent = lipgloss.NewStyle().
		Background(lipgloss.Color(BgSecondary)).
		Foreground(lipgloss.Color(FgPrimary)).
		Padding(0, 2)

	// Menu styles
	s.Menu = lipgloss.NewStyle().
		Background(lipgloss.Color(BgFloat)).
		Foreground(lipgloss.Color(FgPrimary)).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color(Border)).
		Padding(1).
		Width(30)

	s.MenuItem = lipgloss.NewStyle().
		Foreground(lipgloss.Color(FgSecondary)).
		Padding(0, 1)

	s.MenuItemActive = s.MenuItem.Copy().
		Background(lipgloss.Color(Focus)).
		Foreground(lipgloss.Color(BgPrimary)).
		Bold(true)

	// Text styles
	s.Title = lipgloss.NewStyle().
		Foreground(lipgloss.Color(Blue)).
		Bold(true).
		MarginBottom(1)

	s.Subtitle = lipgloss.NewStyle().
		Foreground(lipgloss.Color(Purple)).
		Bold(true)

	s.Body = lipgloss.NewStyle().
		Foreground(lipgloss.Color(FgPrimary))

	s.Code = lipgloss.NewStyle().
		Background(lipgloss.Color(BgSecondary)).
		Foreground(lipgloss.Color(Green)).
		Padding(0, 1)

	s.Comment = lipgloss.NewStyle().
		Foreground(lipgloss.Color(FgComment)).
		Italic(true)

	s.Highlight = lipgloss.NewStyle().
		Background(lipgloss.Color(Yellow)).
		Foreground(lipgloss.Color(BgPrimary)).
		Bold(true)

	// Status styles
	s.StatusGood = lipgloss.NewStyle().
		Foreground(lipgloss.Color(Success)).
		Bold(true)

	s.StatusWarning = lipgloss.NewStyle().
		Foreground(lipgloss.Color(Warning)).
		Bold(true)

	s.StatusError = lipgloss.NewStyle().
		Foreground(lipgloss.Color(Error)).
		Bold(true)

	s.StatusInfo = lipgloss.NewStyle().
		Foreground(lipgloss.Color(Blue)).
		Bold(true)

	// Special element styles
	s.Border = lipgloss.NewStyle().
		Foreground(lipgloss.Color(Border))

	s.Keybind = lipgloss.NewStyle().
		Background(lipgloss.Color(BgAccent)).
		Foreground(lipgloss.Color(Orange)).
		Bold(true).
		Padding(0, 1)

	s.Path = lipgloss.NewStyle().
		Foreground(lipgloss.Color(Cyan)).
		Underline(true)

	s.LineNumber = lipgloss.NewStyle().
		Foreground(lipgloss.Color(FgComment)).
		Width(4).
		Align(lipgloss.Right)

	// Focus indicators
	s.FocusedBorder = lipgloss.NewStyle().
		Border(lipgloss.ThickBorder()).
		BorderForeground(lipgloss.Color(Focus))

	s.UnfocusedBorder = lipgloss.NewStyle().
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(BorderDim))

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
		BorderForeground(lipgloss.Color(Focus))
}

// Unfocused returns the unfocused version of a section style
func (s *Styles) Unfocused(style lipgloss.Style) lipgloss.Style {
	return style.Copy().
		Border(lipgloss.NormalBorder()).
		BorderForeground(lipgloss.Color(BorderDim))
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
