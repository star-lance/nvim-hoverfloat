package view

import (
	"fmt"
	"strings"
	"time"

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

	// Viewport fields removed - no longer using scrollable viewports
	HoverViewport      interface{} // Placeholder to maintain compatibility
	ReferencesViewport interface{}
	DefinitionViewport interface{}
	TypeInfoViewport   interface{}
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
	footerHeight := 2
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

	// Menu system removed for simplicity
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
	spacingNeeded := width - lipgloss.Width(title) - lipgloss.Width(statusAndTime) - 4 // padding
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

	// Header with full width background
	headerText := "📖 Documentation"
	headerPadded := headerText + strings.Repeat(" ", max(0, width-lipgloss.Width(headerText)-4))
	header := s.WithWidth(s.SectionHeader, width).Render(headerPadded)

	// Format hover content directly (no viewport)
	content := formatHoverContent(data.Context.Hover, width-4, s)

	// Use content as-is (simplified, no viewport scrolling)
	contentFormatted := content

	// Join and render section with full width
	sectionContent := lipgloss.JoinVertical(lipgloss.Left, header, contentFormatted)

	return s.WithWidth(sectionStyle, width).Render(sectionContent)
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

	// Header with count and full width
	refCount := data.Context.GetTotalReferences()
	refText := "reference"
	if refCount != 1 {
		refText = "references"
	}
	headerText := fmt.Sprintf("🔗 References (%d %s)", refCount, refText)
	headerPadded := headerText + strings.Repeat(" ", max(0, width-lipgloss.Width(headerText)-4))
	header := s.WithWidth(s.SectionHeader, width).Render(headerPadded)

	// Format references list with consistent background
	content := formatReferences(data.Context, width-4, s)

	// Use content as-is (no special background enforcement)
	contentFormatted := content

	// Join and render section with full width
	sectionContent := lipgloss.JoinVertical(lipgloss.Left, header, contentFormatted)

	return s.WithWidth(sectionStyle, width).Render(sectionContent)
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

	// Header with full width
	headerText := "📍 Definition"
	headerPadded := headerText + strings.Repeat(" ", max(0, width-lipgloss.Width(headerText)-4))
	header := s.WithWidth(s.SectionHeader, width).Render(headerPadded)

	// Format definition location with consistent background
	def := data.Context.Definition
	location := fmt.Sprintf("%s:%d:%d",
		s.Path.Render(truncateString(def.File, width-10)),
		def.Line,
		def.Col,
	)

	// Use location content as-is (no special background enforcement)
	contentFormatted := location

	// Join and render section with full width
	sectionContent := lipgloss.JoinVertical(lipgloss.Left, header, contentFormatted)

	return s.WithWidth(sectionStyle, width).Render(sectionContent)
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

	// Header with full width
	headerText := "🎯 Type Definition"
	headerPadded := headerText + strings.Repeat(" ", max(0, width-lipgloss.Width(headerText)-4))
	header := s.WithWidth(s.SectionHeader, width).Render(headerPadded)

	// Format type definition location with consistent background
	typedef := data.Context.TypeDefinition
	location := fmt.Sprintf("%s:%d:%d",
		s.Path.Render(truncateString(typedef.File, width-10)),
		typedef.Line,
		typedef.Col,
	)

	// Use location content as-is (no special background enforcement)
	contentFormatted := location

	// Join and render section with full width
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
		rendered, err := renderMarkdown(content, width-4, true) // Use dark theme
		if err == nil && rendered != content {
			// Only use rendered if it's actually different (glamour worked)
			return rendered
		}
		// Fall back to simple rendering if markdown parsing fails or returned unchanged
	}

	// Simple text rendering with basic syntax highlighting
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
	// Key bindings help (simplified)
	bindings := []string{
		s.Keybind.Render("hjkl") + " navigate",
		s.Keybind.Render("enter") + " toggle",
		s.Keybind.Render("q") + " quit",
	}

	help := strings.Join(bindings, "  ")

	// Pad to full width
	helpPadded := help + strings.Repeat(" ", max(0, width-lipgloss.Width(help)-4))

	footer := s.WithWidth(s.Footer, width).Render(helpPadded)

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

func max(a, b int) int {
	if a > b {
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

		// Weaker indicators (inline code, links)
		if strings.Contains(line, "`") && !strings.Contains(line, "```") ||
			strings.Contains(line, "[") && strings.Contains(line, "]") ||
			strings.Contains(line, "_") {
			markdownIndicators++
		}
	}

	// Consider it markdown if we have enough indicators
	// For small content (< 3 lines), need at least 1 strong indicator
	// For larger content, need indicators in at least 25% of lines
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
