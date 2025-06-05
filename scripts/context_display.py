#!/usr/bin/env python3
"""
Neovim-styled LSP Context Display Window
Handles terminal buffer control with ANSI escape sequences
"""

import sys
import json
import socket
import os
import threading
import time
from datetime import datetime
from typing import Dict, List, Optional, Any

class NeovimColors:
    """Color scheme matching Neovim's tokyonight theme"""
    # Background colors
    BG_PRIMARY = "\033[48;2;26;27;38m"      # #1a1b26
    BG_SECONDARY = "\033[48;2;36;40;59m"    # #24283b
    BG_ACCENT = "\033[48;2;65;72;104m"      # #414868
    
    # Foreground colors  
    FG_PRIMARY = "\033[38;2;192;202;245m"   # #c0caf5
    FG_SECONDARY = "\033[38;2;169;177;214m" # #a9b1d6
    FG_COMMENT = "\033[38;2;86;95;137m"     # #565f89
    
    # Accent colors
    BLUE = "\033[38;2;122;162;247m"         # #7aa2f7  
    GREEN = "\033[38;2;158;206;106m"        # #9ece6a
    YELLOW = "\033[38;2;224;175;104m"       # #e0af68
    PURPLE = "\033[38;2;187;154;247m"       # #bb9af7
    RED = "\033[38;2;247;118;142m"          # #f7768e
    ORANGE = "\033[38;2;255;158;100m"       # #ff9e64
    
    # Special
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"

class ANSIControl:
    """ANSI escape sequence utilities for terminal control"""
    
    @staticmethod
    def cursor_to(row: int, col: int) -> str:
        """Move cursor to specific position (1-indexed)"""
        return f"\033[{row};{col}H"
    
    @staticmethod
    def clear_screen() -> str:
        """Clear entire screen"""
        return "\033[2J"
    
    @staticmethod
    def clear_line() -> str:
        """Clear current line"""
        return "\033[K"
    
    @staticmethod
    def clear_line_from_cursor() -> str:
        """Clear from cursor to end of line"""
        return "\033[0K"
    
    @staticmethod
    def save_cursor() -> str:
        """Save cursor position"""
        return "\033[s"
    
    @staticmethod
    def restore_cursor() -> str:
        """Restore cursor position"""
        return "\033[u"
    
    @staticmethod
    def hide_cursor() -> str:
        """Hide cursor"""
        return "\033[?25l"
    
    @staticmethod
    def show_cursor() -> str:
        """Show cursor"""
        return "\033[?25h"
    
    @staticmethod
    def alternate_screen() -> str:
        """Switch to alternate screen buffer"""
        return "\033[?1049h"
    
    @staticmethod
    def normal_screen() -> str:
        """Switch back to normal screen buffer"""
        return "\033[?1049l"

class ContextWindow:
    """Main class for managing the LSP context display window"""
    
    def __init__(self, socket_path: str = "/tmp/nvim_context.sock"):
        self.socket_path = socket_path
        self.socket = None
        self.running = False
        self.current_data = {}
        
        # Window dimensions
        self.width = 80
        self.height = 25
        
        # Section positions (row numbers)
        self.sections = {
            'header': 1,
            'file_info': 3, 
            'hover_start': 5,
            'definition': 15,
            'references': 17,
            'footer': self.height - 1
        }
        
    def setup_terminal(self):
        """Initialize terminal with proper settings"""
        print(ANSIControl.alternate_screen(), end='')
        print(ANSIControl.hide_cursor(), end='')
        print(ANSIControl.clear_screen(), end='')
        print(NeovimColors.BG_PRIMARY, end='')
        sys.stdout.flush()
        
    def cleanup_terminal(self):
        """Restore terminal to normal state"""
        print(ANSIControl.show_cursor(), end='')
        print(ANSIControl.normal_screen(), end='')
        print(NeovimColors.RESET, end='')
        sys.stdout.flush()
        
    def draw_border(self, row: int, width: int, style: str = "─"):
        """Draw a horizontal border at specified row"""
        print(ANSIControl.cursor_to(row, 1), end='')
        print(NeovimColors.BG_PRIMARY + NeovimColors.FG_COMMENT, end='')
        print("├" + style * (width - 2) + "┤", end='')
        print(NeovimColors.RESET, end='')
        
    def draw_header(self):
        """Draw the header section"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        
        # Main header
        print(ANSIControl.cursor_to(self.sections['header'], 1), end='')
        print(NeovimColors.BG_ACCENT + NeovimColors.BOLD + NeovimColors.BLUE, end='')
        print("🔍 NEOVIM LSP CONTEXT", end='')
        
        # Right-aligned timestamp
        spaces_needed = self.width - 22 - len(timestamp) - 1
        print(" " * spaces_needed, end='')
        print(NeovimColors.DIM + f"[{timestamp}]", end='')
        print(NeovimColors.RESET, end='')
        
        # Border under header
        self.draw_border(self.sections['header'] + 1, self.width)
        
    def draw_file_info(self, data: Dict[str, Any]):
        """Draw current file information section"""
        file_name = data.get('file', 'Unknown')
        line = data.get('line', 0)
        col = data.get('col', 0)
        
        print(ANSIControl.cursor_to(self.sections['file_info'], 1), end='')
        print(NeovimColors.BG_PRIMARY, end='')
        print(NeovimColors.BLUE + "📄 Current File: ", end='')
        print(NeovimColors.FG_PRIMARY + file_name, end='')
        print(NeovimColors.FG_SECONDARY + f" (Line {line}, Col {col})", end='')
        print(ANSIControl.clear_line_from_cursor(), end='')
        print(NeovimColors.RESET, end='')
        
    def draw_hover_info(self, hover_data: List[str]):
        """Draw LSP hover information section"""
        start_row = self.sections['hover_start']
        
        # Section title
        print(ANSIControl.cursor_to(start_row, 1), end='')
        print(NeovimColors.BG_PRIMARY + NeovimColors.YELLOW + "📖 Documentation:", end='')
        print(ANSIControl.clear_line_from_cursor() + NeovimColors.RESET, end='')
        
        # Content
        max_lines = self.sections['definition'] - start_row - 2
        for i, line in enumerate(hover_data[:max_lines]):
            print(ANSIControl.cursor_to(start_row + 1 + i, 3), end='')
            print(NeovimColors.BG_PRIMARY + NeovimColors.FG_PRIMARY, end='')
            print(line[:self.width - 4], end='')  # Truncate if too long
            print(ANSIControl.clear_line_from_cursor() + NeovimColors.RESET, end='')
        
        # Clear any remaining lines in this section
        for i in range(len(hover_data), max_lines):
            print(ANSIControl.cursor_to(start_row + 1 + i, 1), end='')
            print(NeovimColors.BG_PRIMARY + ANSIControl.clear_line() + NeovimColors.RESET, end='')
            
    def draw_definition_info(self, definition: Dict[str, Any]):
        """Draw symbol definition information"""
        if not definition:
            return
            
        print(ANSIControl.cursor_to(self.sections['definition'], 1), end='')
        print(NeovimColors.BG_PRIMARY + NeovimColors.GREEN + "📍 Defined in: ", end='')
        
        file_name = definition.get('file', 'Unknown')
        line = definition.get('line', 0)
        col = definition.get('col', 0)
        
        print(NeovimColors.FG_PRIMARY + f"{file_name}:{line}:{col}", end='')
        print(ANSIControl.clear_line_from_cursor() + NeovimColors.RESET, end='')
        
    def draw_references_info(self, references: List[Dict[str, Any]], count: int):
        """Draw references information section"""
        start_row = self.sections['references']
        
        # Section title
        ref_text = "reference" if count == 1 else "references"
        print(ANSIControl.cursor_to(start_row, 1), end='')
        print(NeovimColors.BG_PRIMARY + NeovimColors.PURPLE + f"🔗 References ({count} {ref_text} found):", end='')
        print(ANSIControl.clear_line_from_cursor() + NeovimColors.RESET, end='')
        
        # Reference list
        max_lines = self.sections['footer'] - start_row - 2
        for i, ref in enumerate(references[:max_lines]):
            print(ANSIControl.cursor_to(start_row + 1 + i, 3), end='')
            print(NeovimColors.BG_PRIMARY + NeovimColors.FG_SECONDARY + "• ", end='')
            
            file_name = ref.get('file', 'Unknown')
            line = ref.get('line', 0)
            print(f"{file_name}:{line}", end='')
            print(ANSIControl.clear_line_from_cursor() + NeovimColors.RESET, end='')
        
        # Show "and X more" if there are more references
        if len(references) > max_lines:
            remaining = len(references) - max_lines
            print(ANSIControl.cursor_to(start_row + max_lines + 1, 3), end='')
            print(NeovimColors.BG_PRIMARY + NeovimColors.FG_COMMENT, end='')
            print(f"... and {remaining} more", end='')
            print(ANSIControl.clear_line_from_cursor() + NeovimColors.RESET, end='')
            
    def draw_footer(self):
        """Draw footer with controls info"""
        print(ANSIControl.cursor_to(self.sections['footer'], 1), end='')
        print(NeovimColors.BG_ACCENT + NeovimColors.FG_COMMENT, end='')
        footer_text = " Ctrl+C to exit • Updates automatically as you move cursor in Neovim "
        padding = (self.width - len(footer_text)) // 2
        print(" " * padding + footer_text + " " * padding, end='')
        print(NeovimColors.RESET, end='')
        
    def update_display(self, data: Dict[str, Any]):
        """Update the entire display with new data"""
        # Save cursor and prepare
        print(ANSIControl.save_cursor(), end='')
        
        # Draw all sections
        self.draw_header()
        self.draw_file_info(data)
        
        # Draw hover information if available
        if 'hover' in data and data['hover']:
            self.draw_hover_info(data['hover'])
        else:
            # Clear hover section
            for i in range(self.sections['hover_start'], self.sections['definition']):
                print(ANSIControl.cursor_to(i, 1), end='')
                print(NeovimColors.BG_PRIMARY + ANSIControl.clear_line() + NeovimColors.RESET, end='')
        
        # Draw definition if available
        if 'definition' in data:
            self.draw_definition_info(data['definition'])
            
        # Draw references if available  
        if 'references' in data:
            count = data.get('references_count', len(data['references']))
            self.draw_references_info(data['references'], count)
        
        self.draw_footer()
        
        # Restore cursor and flush
        print(ANSIControl.restore_cursor(), end='')
        sys.stdout.flush()
        
    def show_waiting_message(self):
        """Show initial waiting message"""
        print(ANSIControl.cursor_to(self.height // 2, 1), end='')
        center_col = (self.width - 40) // 2
        print(ANSIControl.cursor_to(self.height // 2, center_col), end='')
        print(NeovimColors.BG_PRIMARY + NeovimColors.FG_COMMENT, end='')
        print("Waiting for cursor movement in Neovim...", end='')
        print(NeovimColors.RESET, end='')
        sys.stdout.flush()
        
    def start_socket_server(self):
        """Start the Unix domain socket server"""
        # Remove existing socket file
        try:
            os.unlink(self.socket_path)
        except OSError:
            pass
            
        # Create socket
        self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket.bind(self.socket_path)
        self.socket.listen(1)
        
        print(f"Context display listening on {self.socket_path}", file=sys.stderr)
        
        while self.running:
            try:
                conn, addr = self.socket.accept()
                with conn:
                    while self.running:
                        data = conn.recv(4096)
                        if not data:
                            break
                            
                        try:
                            # Parse JSON message
                            message = json.loads(data.decode('utf-8'))
                            if message.get('type') == 'context_update':
                                self.current_data = message.get('data', {})
                                self.update_display(self.current_data)
                        except json.JSONDecodeError:
                            continue
                            
            except OSError:
                if self.running:
                    print("Socket error occurred", file=sys.stderr)
                break
                
    def run(self):
        """Main run loop"""
        try:
            self.setup_terminal()
            self.draw_header()
            self.draw_footer() 
            self.show_waiting_message()
            
            self.running = True
            
            # Start socket server in background thread
            socket_thread = threading.Thread(target=self.start_socket_server, daemon=True)
            socket_thread.start()
            
            # Main loop - just keep the program alive
            try:
                while self.running:
                    time.sleep(0.1)
            except KeyboardInterrupt:
                pass
                
        finally:
            self.running = False
            self.cleanup_terminal()
            if self.socket:
                self.socket.close()
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass

def main():
    """Entry point"""
    socket_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/nvim_context.sock"
    
    try:
        window = ContextWindow(socket_path)
        window.run()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
