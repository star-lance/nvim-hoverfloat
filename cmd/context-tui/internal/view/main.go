package view

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/star-lance/nvim-hoverfloat/cmd/context-tui/internal/socket"
	"github.com/star-lance/nvim-hoverfloat/cmd/context-tui/internal/styles"
)

// ViewData contains all the data needed to render the view
type ViewData struct {
	Context        *socket.ContextData
	ErrorMsg       string
	Connected      bool
	LastUpdate     time.Time
	Focus          int // FocusArea as int
	ShowHover      bool
	ShowReferences bool
	ShowDefinition bool
	ShowTypeInfo   bool
	MenuVisible    bool
	MenuSelection  int
}

// FocusArea constants (matching the model)
const (
	FocusHover = iota
	FocusReferences
	FocusDefinition
	FocusTypeDefinition
)

// Render creates the complete UI view
func Render(width, height int, data *ViewData, s *styles.Styles) string {
	// Calculate layout dimensions
	headerHeight := 3
	footerHeight := 3
	contentHeight := height - headerHeight - footerHeight

	// Build the main sections
	header := renderHeader(width, data, s)
	content := renderContent(width, contentHeight, data, s)
	footer := renderFooter(width, data, s)

	// Combine sections
	view := lipgloss.JoinVertical(
		lipgloss.Left,
		header,
		content,
		footer,
	)

	// Overlay menu if visible
	if data.MenuVisible {
		menu := renderMenu(data, s)
		// Position menu in center-right
		menuX := width - 35
		menuY := 5
		view = overlayMenu(view, menu, menuX, menuY)
	}

	return view
}

// renderHeader creates the header section
func renderHeader(width int, data *ViewData, s *styles.Styles) string {
	title := "🔍 NEOVIM LSP CONTEXT"

	// Status indicator
	var status string
	if data.Connected {
		status = s.StatusGood.Render("● Connected")
	} else {
		status = s.StatusError.Render("● Disconnected")
	}

	// Timestamp
	var timestamp string
	if !data.LastUpdate.IsZero() {
		timestamp = data.LastUpdate.Format("15:04:05")
	} else {
		timestamp = "--:--:--"
	}

	// Build header line
	headerContent := fmt.Sprintf("%s%s%s%s%s",
		s.Title.Render(title),
		strings.Repeat(" ", max(0, width-len(title)-len(status)-len(timestamp)-10)),
		status,
		"  ",
		s.Comment.Render(timestamp),
	)

	// Current file info
	var fileInfo string
	if data.Context != nil {
		icon := s.FileIcon(data.Context.File)
		fileInfo = fmt.Sprintf("%s %s:%d:%d",
			icon,
			s.Path.Render(truncateString(data.Context.File, width-20)),
			data.Context.Line,
			data.Context.Col,
		)
	} else {
		fileInfo = s.Comment.Render("No context data")
	}

	header := lipgloss.JoinVertical(
		lipgloss.Left,
		s.WithWidth(s.Header, width).Render(headerContent),
		s.WithWidth(s.Content, width).Render(fileInfo),
		s.WithWidth(s.Border, width).Render(strings.Repeat("─", width)),
	)

	return header
}

// renderContent creates the main content area
func renderContent(width, height int, data *ViewData, s *styles.Styles) string {
	if data.Context == nil {
		return renderWaitingMessage(width, height, data, s)
	}

	if data.ErrorMsg != "" {
		return renderError(width, height, data, s)
	}

	// Calculate section dimensions
	sections := []string{}
	sectionHeight := height / 4 // Base height for each section

	// Build visible sections
	if data.ShowHover && data.Context.HasHover() {
		section := renderHoverSection(width, sectionHeight, data, s)
		sections = append(sections, section)
	}

	if data.ShowReferences && data.Context.HasReferences() {
		section := renderReferencesSection(width, sectionHeight, data, s)
		sections = append(sections, section)
	}

	if data.ShowDefinition && data.Context.HasDefinition() {
		section := renderDefinitionSection(width, sectionHeight, data, s)
		sections = append(sections, section)
	}

	if data.ShowTypeInfo && data.Context.HasTypeDefinition() {
		section := renderTypeDefinitionSection(width, sectionHeight, data, s)
		sections = append(sections, section)
	}

	if len(sections) == 0 {
		return renderNoDataMessage(width, height, s)
	}

	// Join sections with spacing
	content := strings.Join(sections, "\n")

	// Ensure content fits in available height
	return truncateContent(content, height)
}

// renderHoverSection creates the hover documentation section
func renderHoverSection(width, height int, data *ViewData, s *styles.Styles) string {
	if data.Context == nil || !data.Context.HasHover() {
		return ""
	}

	focused := data.Focus == FocusHover
	sectionStyle := s.Section
	if focused {
		sectionStyle = s.SectionFocused
	}

	header := s.SectionHeader.Render("📖 Documentation")

	// Format hover content
	content := formatHoverContent(data.Context.Hover, width-4, s)

	section := sectionStyle.Copy().
		Width(width - 2).
		Height(height - 2).
		Render(lipgloss.JoinVertical(lipgloss.Left, header, content))

	return section
}

// renderReferencesSection creates the references section
func renderReferencesSection(width, height int, data *ViewData, s *styles.Styles) string {
	if data.Context == nil || !data.Context.HasReferences() {
		return ""
	}

	focused := data.Focus == FocusReferences
	sectionStyle := s.Section
	if focused {
		sectionStyle = s.SectionFocused
	}

	// Header with count
	refCount := data.Context.GetTotalReferences()
	refText := "reference"
	if refCount != 1 {
		refText = "references"
	}
	header := s.SectionHeader.Render(fmt.Sprintf("🔗 References (%d %s)", refCount, refText))

	// Format references list
	content := formatReferences(data.Context, width-4, s)

	section := sectionStyle.Copy().
		Width(width - 2).
		Height(height - 2).
		Render(lipgloss.JoinVertical(lipgloss.Left, header, content))

	return section
}

// renderDefinitionSection creates the definition section
func renderDefinitionSection(width, height int, data *ViewData, s *styles.Styles) string {
	if data.Context == nil || !data.Context.HasDefinition() {
		return ""
	}

	focused := data.Focus == FocusDefinition
	sectionStyle := s.Section
	if focused {
		sectionStyle = s.SectionFocused
	}

	header := s.SectionHeader.Render("📍 Definition")

	// Format definition location
	def := data.Context.Definition
	location := fmt.Sprintf("%s:%d:%d",
		s.Path.Render(truncateString(def.File, width-10)),
		def.Line,
		def.Col,
	)

	content := s.Body.Render(location)

	section := sectionStyle.Copy().
		Width(width - 2).
		Height(height - 2).
		Render(lipgloss.JoinVertical(lipgloss.Left, header, content))

	return section
}

// renderTypeDefinitionSection creates the type definition section
func renderTypeDefinitionSection(width, height int, data *ViewData, s *styles.Styles) string {
	if data.Context == nil || !data.Context.HasTypeDefinition() {
		return ""
	}

	focused := data.Focus == FocusTypeDefinition
	sectionStyle := s.Section
	if focused {
		sectionStyle = s.SectionFocused
	}

	header := s.SectionHeader.Render("🎯 Type Definition")

	// Format type definition location
	typedef := data.Context.TypeDefinition
	location := fmt.Sprintf("%s:%d:%d",
		s.Path.Render(truncateString(typedef.File, width-10)),
		typedef.Line,
		typedef.Col,
	)

	content := s.Body.Render(location)

	section := sectionStyle.Copy().
		Width(width - 2).
		Height(height - 2).
		Render(lipgloss.JoinVertical(lipgloss.Left, header, content))

	return section
}

// renderMenu creates the interactive menu overlay
func renderMenu(data *ViewData, s *styles.Styles) string {
	title := s.Subtitle.Render("Toggle Sections")

	items := []string{
		formatMenuItem("H", "Hover", data.ShowHover, data.MenuSelection == 0, s),
		formatMenuItem("R", "References", data.ShowReferences, data.MenuSelection == 1, s),
		formatMenuItem("D", "Definition", data.ShowDefinition, data.MenuSelection == 2, s),
		formatMenuItem("T", "Type Info", data.ShowTypeInfo, data.MenuSelection == 3, s),
	}

	content := lipgloss.JoinVertical(lipgloss.Left, append([]string{title, ""}, items...)...)

	help := s.Comment.Render("j/k: navigate  enter: toggle  esc: close")

	menu := s.Menu.Render(lipgloss.JoinVertical(
		lipgloss.Left,
		content,
		"",
		help,
	))

	return menu
}

// formatMenuItem formats a single menu item
func formatMenuItem(key, label string, enabled, selected bool, s *styles.Styles) string {
	var style lipgloss.Style
	if selected {
		style = s.MenuItemActive
	} else {
		style = s.MenuItem
	}

	statusIcon := "○"
	if enabled {
		statusIcon = "●"
	}

	return style.Render(fmt.Sprintf("%s %s %s", s.Keybind.Render(key), statusIcon, label))
}

// Helper functions

func formatHoverContent(hover []string, width int, s *styles.Styles) string {
	if len(hover) == 0 {
		return s.Comment.Render("No documentation available")
	}

	var lines []string
	for _, line := range hover {
		// Simple syntax highlighting for code blocks
		if strings.HasPrefix(line, "```") {
			if strings.Contains(line, "```") && len(line) > 3 {
				// Language specification
				lines = append(lines, s.Code.Render(line))
			} else {
				// Code block delimiter
				lines = append(lines, s.Comment.Render(line))
			}
		} else if strings.HasPrefix(line, "    ") || strings.HasPrefix(line, "\t") {
			// Indented code
			lines = append(lines, s.Code.Render(line))
		} else if strings.HasPrefix(line, "#") {
			// Markdown headers
			lines = append(lines, s.Highlight.Render(line))
		} else {
			// Regular text
			lines = append(lines, s.Body.Render(truncateString(line, width)))
		}
	}

	return strings.Join(lines, "\n")
}

func formatReferences(context *socket.ContextData, width int, s *styles.Styles) string {
	refs := context.GetDisplayableReferences()
	if len(refs) == 0 {
		return s.Comment.Render("No references found")
	}

	var lines []string
	for i, ref := range refs {
		if i >= 10 { // Limit displayed references
			break
		}

		location := fmt.Sprintf("• %s:%d",
			truncateString(ref.File, width-10),
			ref.Line,
		)
		lines = append(lines, s.Body.Render(location))
	}

	// Add "more" indicator if needed
	if more := context.GetMoreReferencesCount(); more > 0 {
		lines = append(lines, s.Comment.Render(fmt.Sprintf("... and %d more", more)))
	}

	return strings.Join(lines, "\n")
}

func renderWaitingMessage(width, height int, data *ViewData, s *styles.Styles) string {
	message := "Waiting for cursor movement in Neovim..."
	if !data.Connected {
		message = "Connecting to Neovim..."
	}

	content := s.Comment.Render(message)

	// Center the message
	centerY := height / 2
	padding := strings.Repeat("\n", max(0, centerY-2))

	return padding + centerContent(content, width)
}

func renderError(width, height int, data *ViewData, s *styles.Styles) string {
	title := s.StatusError.Render("⚠️  Error")
	message := s.Body.Render(data.ErrorMsg)

	content := lipgloss.JoinVertical(lipgloss.Left, title, "", message)

	// Center the error message
	centerY := height / 2
	padding := strings.Repeat("\n", max(0, centerY-3))

	return padding + centerContent(content, width)
}

func renderNoDataMessage(width, height int, s *styles.Styles) string {
	message := s.Comment.Render("No LSP data available for current cursor position")

	// Center the message
	centerY := height / 2
	padding := strings.Repeat("\n", max(0, centerY-1))

	return padding + centerContent(message, width)
}

func renderFooter(width int, data *ViewData, s *styles.Styles) string {
	// Key bindings help
	bindings := []string{
		s.Keybind.Render("?") + " menu",
		s.Keybind.Render("hjkl") + " navigate",
		s.Keybind.Render("enter") + " toggle",
		s.Keybind.Render("q") + " quit",
	}

	help := strings.Join(bindings, "  ")

	footer := s.WithWidth(s.Footer, width).Render(help)

	return footer
}

// Utility functions

func overlayMenu(base, menu string, x, y int) string {
	// This is a simplified overlay - in a real implementation,
	// you'd need more sophisticated positioning
	return base + "\n" + menu
}

func centerContent(content string, width int) string {
	lines := strings.Split(content, "\n")
	var centeredLines []string

	for _, line := range lines {
		padding := max(0, (width-lipgloss.Width(line))/2)
		centeredLines = append(centeredLines, strings.Repeat(" ", padding)+line)
	}

	return strings.Join(centeredLines, "\n")
}

func truncateString(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}

	if maxLen <= 3 {
		return "..."
	}

	return s[:maxLen-3] + "..."
}

func truncateContent(content string, maxHeight int) string {
	lines := strings.Split(content, "\n")
	if len(lines) <= maxHeight {
		return content
	}

	return strings.Join(lines[:maxHeight], "\n")
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
