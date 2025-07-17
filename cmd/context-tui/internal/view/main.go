package view

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/viewport"
	"github.com/charmbracelet/glamour"
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
	Focus          int
	ShowHover      bool
	ShowReferences bool
	ShowDefinition bool
	ShowTypeInfo   bool
	MenuVisible    bool
	MenuSelection  int

	// Viewport fields for scrolling
	HoverViewport      interface{} // *viewport.Model
	ReferencesViewport interface{} // *viewport.Model
	DefinitionViewport interface{} // *viewport.Model
	TypeInfoViewport   interface{} // *viewport.Model
}

// FocusArea constants
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
	footerHeight := 3 // Increased for better help text
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

	return view
}

// renderHeader creates the header section
func renderHeader(width int, data *ViewData, s *styles.Styles) string {
	// Header line with status
	title := "hoverfloat"

	var status string
	if data.Connected {
		status = s.StatusGood.Render("● Connected")
	} else {
		status = s.StatusError.Render("● Disconnected")
	}

	var timestamp string
	if !data.LastUpdate.IsZero() {
		timestamp = data.LastUpdate.Format("15:04:05")
	} else {
		timestamp = "--:--:--"
	}

	// Calculate spacing to fill entire width
	statusAndTime := fmt.Sprintf("%s  %s", status, s.Comment.Render(timestamp))
	spacingNeeded := width - lipgloss.Width(title) - lipgloss.Width(statusAndTime) - 4
	if spacingNeeded < 0 {
		spacingNeeded = 0
	}

	headerLine1 := fmt.Sprintf("%s%s%s",
		title,
		strings.Repeat(" ", spacingNeeded),
		statusAndTime)

	// File info line
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

	// Pad file info to full width
	fileInfoPadded := fileInfo + strings.Repeat(" ", max(0, width-lipgloss.Width(fileInfo)-4))

	header := lipgloss.JoinVertical(
		lipgloss.Left,
		s.WithWidth(s.Header, width).Render(headerLine1),
		s.WithWidth(s.Content, width).Render(fileInfoPadded),
	)

	return header
}

// renderContent creates the main content area with viewports
func renderContent(width, height int, data *ViewData, s *styles.Styles) string {
	if data.Context == nil {
		return renderWaitingMessage(width, height, data, s)
	}

	if data.ErrorMsg != "" {
		return renderError(width, height, data, s)
	}

	sections := []string{}
	remainingHeight := height

	// Render visible sections with viewports
	if data.ShowHover && data.Context.HasHover() {
		section := renderHoverSectionWithViewport(width, remainingHeight, data, s)
		sections = append(sections, section)
		remainingHeight -= countLines(section) + 1
	}

	if data.ShowReferences && data.Context.HasReferences() && remainingHeight > 4 {
		section := renderReferencesSectionWithViewport(width, remainingHeight, data, s)
		sections = append(sections, section)
		remainingHeight -= countLines(section) + 1
	}

	if data.ShowDefinition && data.Context.HasDefinition() && remainingHeight > 4 {
		section := renderDefinitionSectionWithViewport(width, remainingHeight, data, s)
		sections = append(sections, section)
		remainingHeight -= countLines(section) + 1
	}

	if data.ShowTypeInfo && data.Context.HasTypeDefinition() && remainingHeight > 4 {
		section := renderTypeDefinitionSectionWithViewport(width, remainingHeight, data, s)
		sections = append(sections, section)
	}

	if len(sections) == 0 {
		return renderNoDataMessage(width, height, s)
	}

	// Join sections
	content := strings.Join(sections, "\n")
	return truncateContent(content, height)
}

// Render sections with viewport support
func renderHoverSectionWithViewport(width, height int, data *ViewData, s *styles.Styles) string {
	if data.Context == nil || !data.Context.HasHover() {
		return ""
	}

	focused := data.Focus == FocusHover
	sectionStyle := s.Section
	if focused {
		sectionStyle = s.SectionFocused
	}

	// Header
	headerText := "📖 Documentation"
	if vp, ok := data.HoverViewport.(*viewport.Model); ok && vp != nil {
		scrollInfo := fmt.Sprintf(" [%d%%]", vp.ScrollPercent())
		headerText += s.Comment.Render(scrollInfo)
	}
	headerPadded := headerText + strings.Repeat(" ", max(0, width-lipgloss.Width(headerText)-4))
	header := s.WithWidth(s.SectionHeader, width).Render(headerPadded)

	// Content from viewport or fallback
	var contentFormatted string
	if vp, ok := data.HoverViewport.(*viewport.Model); ok && vp != nil {
		// Use viewport's view
		contentFormatted = vp.View()
	} else {
		// Fallback to static content
		content := formatHoverContent(data.Context.Hover, width-4, s)
		maxLines := min(height-3, 10)
		contentFormatted = truncateToLines(content, maxLines)
	}

	// Join and render section
	sectionContent := lipgloss.JoinVertical(lipgloss.Left, header, contentFormatted)
	return s.WithWidth(sectionStyle, width).Render(sectionContent)
}

func renderReferencesSectionWithViewport(width, height int, data *ViewData, s *styles.Styles) string {
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
	headerText := fmt.Sprintf("🔗 References (%d %s)", refCount, refText)
	if vp, ok := data.ReferencesViewport.(*viewport.Model); ok && vp != nil {
		scrollInfo := fmt.Sprintf(" [%d%%]", vp.ScrollPercent())
		headerText += s.Comment.Render(scrollInfo)
	}
	headerPadded := headerText + strings.Repeat(" ", max(0, width-lipgloss.Width(headerText)-4))
	header := s.WithWidth(s.SectionHeader, width).Render(headerPadded)

	// Content from viewport or fallback
	var contentFormatted string
	if vp, ok := data.ReferencesViewport.(*viewport.Model); ok && vp != nil {
		contentFormatted = vp.View()
	} else {
		content := formatReferences(data.Context, width-4, s)
		maxLines := min(height-3, 8)
		contentFormatted = truncateToLines(content, maxLines)
	}

	// Join and render section
	sectionContent := lipgloss.JoinVertical(lipgloss.Left, header, contentFormatted)
	return s.WithWidth(sectionStyle, width).Render(sectionContent)
}

func renderDefinitionSectionWithViewport(width, height int, data *ViewData, s *styles.Styles) string {
	if data.Context == nil || !data.Context.HasDefinition() {
		return ""
	}

	focused := data.Focus == FocusDefinition
	sectionStyle := s.Section
	if focused {
		sectionStyle = s.SectionFocused
	}

	// Header
	headerText := "📍 Definition"
	headerPadded := headerText + strings.Repeat(" ", max(0, width-lipgloss.Width(headerText)-4))
	header := s.WithWidth(s.SectionHeader, width).Render(headerPadded)

	// Content from viewport or fallback
	var contentFormatted string
	if vp, ok := data.DefinitionViewport.(*viewport.Model); ok && vp != nil {
		contentFormatted = vp.View()
	} else {
		def := data.Context.Definition
		location := fmt.Sprintf("%s:%d:%d",
			s.Path.Render(truncateString(def.File, width-10)),
			def.Line,
			def.Col,
		)
		contentFormatted = location
	}

	// Join and render section
	sectionContent := lipgloss.JoinVertical(lipgloss.Left, header, contentFormatted)
	return s.WithWidth(sectionStyle, width).Render(sectionContent)
}

func renderTypeDefinitionSectionWithViewport(width, height int, data *ViewData, s *styles.Styles) string {
	if data.Context == nil || !data.Context.HasTypeDefinition() {
		return ""
	}

	focused := data.Focus == FocusTypeDefinition
	sectionStyle := s.Section
	if focused {
		sectionStyle = s.SectionFocused
	}

	// Header
	headerText := "🎯 Type Definition"
	headerPadded := headerText + strings.Repeat(" ", max(0, width-lipgloss.Width(headerText)-4))
	header := s.WithWidth(s.SectionHeader, width).Render(headerPadded)

	// Content from viewport or fallback
	var contentFormatted string
	if vp, ok := data.TypeInfoViewport.(*viewport.Model); ok && vp != nil {
		contentFormatted = vp.View()
	} else {
		typedef := data.Context.TypeDefinition
		location := fmt.Sprintf("%s:%d:%d",
			s.Path.Render(truncateString(typedef.File, width-10)),
			typedef.Line,
			typedef.Col,
		)
		contentFormatted = location
	}

	// Join and render section
	sectionContent := lipgloss.JoinVertical(lipgloss.Left, header, contentFormatted)
	return s.WithWidth(sectionStyle, width).Render(sectionContent)
}

// Helper functions
func formatHoverContent(hover []string, width int, s *styles.Styles) string {
	if len(hover) == 0 {
		return s.Comment.Render("No documentation available")
	}

	// Check if content appears to be markdown
	if isMarkdownContent(hover) {
		// Join all lines and render as markdown
		content := strings.Join(hover, "\n")
		rendered, err := renderMarkdown(content, width-4, true)
		if err == nil && rendered != content {
			return rendered
		}
	}

	// Simple text rendering with basic syntax highlighting
	var lines []string
	for _, line := range hover {
		// Simple syntax highlighting for code blocks
		if strings.HasPrefix(line, "```") {
			if strings.Contains(line, "```") && len(line) > 3 {
				lines = append(lines, s.Code.Render(line))
			} else {
				lines = append(lines, s.Comment.Render(line))
			}
		} else if strings.HasPrefix(line, "    ") || strings.HasPrefix(line, "\t") {
			lines = append(lines, s.Code.Render(line))
		} else if strings.HasPrefix(line, "#") {
			lines = append(lines, s.Highlight.Render(line))
		} else {
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
		if i >= 10 {
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
	// Enhanced key bindings help
	bindings := []string{
		s.Keybind.Render("hjkl") + " nav",
		s.Keybind.Render("↵") + " toggle",
		s.Keybind.Render("g/G") + " top/bot",
		s.Keybind.Render("^u/^d") + " page",
		s.Keybind.Render("+/-") + " resize",
		s.Keybind.Render("v") + " select",
		s.Keybind.Render("?") + " help",
		s.Keybind.Render("q") + " quit",
	}

	help := strings.Join(bindings, "  ")

	// Show current mode
	var modeIndicator string
	if data.Focus == FocusHover {
		modeIndicator = s.StatusInfo.Render("[Hover]")
	} else if data.Focus == FocusReferences {
		modeIndicator = s.StatusInfo.Render("[References]")
	} else if data.Focus == FocusDefinition {
		modeIndicator = s.StatusInfo.Render("[Definition]")
	} else if data.Focus == FocusTypeDefinition {
		modeIndicator = s.StatusInfo.Render("[Type]")
	}

	// Combine help and mode
	footerContent := help + "  " + modeIndicator

	// Pad to full width
	footerPadded := footerContent + strings.Repeat(" ", max(0, width-lipgloss.Width(footerContent)-4))

	footer := s.WithWidth(s.Footer, width).Render(footerPadded)

	return footer
}

// Utility functions
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

func truncateToLines(content string, maxLines int) string {
	lines := strings.Split(content, "\n")
	if len(lines) <= maxLines {
		return content
	}
	return strings.Join(lines[:maxLines], "\n")
}

func countLines(content string) int {
	return strings.Count(content, "\n") + 1
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// isMarkdownContent detects if content contains markdown formatting
func isMarkdownContent(content []string) bool {
	markdownIndicators := 0
	totalLines := len(content)

	for _, line := range content {
		trimmed := strings.TrimSpace(line)

		// Strong indicators (likely markdown)
		if strings.Contains(line, "```") ||
			strings.HasPrefix(trimmed, "# ") ||
			strings.HasPrefix(trimmed, "## ") ||
			strings.HasPrefix(trimmed, "### ") ||
			strings.Contains(line, "**") ||
			strings.Contains(line, "__") ||
			strings.HasPrefix(trimmed, "- ") ||
			strings.HasPrefix(trimmed, "* ") ||
			strings.HasPrefix(trimmed, "+ ") ||
			strings.HasPrefix(trimmed, "> ") {
			markdownIndicators++
		}

		// Weaker indicators
		if strings.Contains(line, "`") && !strings.Contains(line, "```") ||
			strings.Contains(line, "[") && strings.Contains(line, "]") ||
			strings.Contains(line, "_") {
			markdownIndicators++
		}
	}

	// Consider it markdown if we have enough indicators
	if totalLines <= 3 {
		return markdownIndicators >= 1
	}

	return float64(markdownIndicators)/float64(totalLines) >= 0.25
}

// renderMarkdown uses glamour to render markdown content
func renderMarkdown(content string, width int, darkTheme bool) (string, error) {
	// Use dark theme for consistency
	style := "dark"

	var options []glamour.TermRendererOption
	options = append(options, glamour.WithStandardStyle(style))
	options = append(options, glamour.WithWordWrap(width))
	options = append(options, glamour.WithEmoji())

	renderer, err := glamour.NewTermRenderer(options...)
	if err != nil {
		return content, err
	}

	rendered, err := renderer.Render(content)
	if err != nil {
		return content, err
	}

	result := strings.TrimSpace(rendered)
	if result == "" {
		return content, fmt.Errorf("empty result")
	}

	return result, nil
}
