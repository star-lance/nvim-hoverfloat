-- lua/hoverfloat/display.lua - Display script generation and formatting
local M = {}

local PROGRAM_PATH = "/tmp/nvim_context_display"

-- Create the display program
function M.create_program()
  local program_content = M._generate_program_content()
  
  local file = io.open(PROGRAM_PATH, "w")
  if file then
    file:write(program_content)
    file:close()
    vim.fn.system("chmod +x " .. PROGRAM_PATH)
    return PROGRAM_PATH
  end
  return nil
end

-- Clean up the display program
function M.cleanup()
  vim.fn.system("rm -f " .. PROGRAM_PATH)
end

-- Generate the Python display program content
function M._generate_program_content()
  return [[#!/usr/bin/env python3

import sys
import json
from datetime import datetime

class ContextDisplay:
    def __init__(self):
        self.colors = {
            'header': '\033[1;34m',
            'title': '\033[1;36m',
            'file': '\033[1;36m',
            'documentation': '\033[1;33m',
            'definition': '\033[1;32m',
            'references': '\033[1;35m',
            'reference_item': '\033[0;90m',
            'error': '\033[0;31m',
            'info': '\033[0;90m',
            'reset': '\033[0m'
        }
    
    def clear_screen(self):
        print("\033[2J\033[H", end="")
    
    def print_header(self):
        border = "━" * 120
        print(f"{self.colors['header']}{border}{self.colors['reset']}")
        print(f"{self.colors['title']}🔍 NEOVIM CONTEXT INFORMATION{self.colors['reset']}")
        print(f"{self.colors['header']}{border}{self.colors['reset']}")
        print()
    
    def print_footer(self):
        border = "━" * 120
        timestamp = datetime.now().strftime('%H:%M:%S')
        print()
        print(f"{self.colors['header']}{border}{self.colors['reset']}")
        print(f"{self.colors['info']}Updated: {timestamp}{self.colors['reset']}")
    
    def display_error(self, error_msg):
        print(f"{self.colors['error']}{error_msg}{self.colors['reset']}")
    
    def display_waiting(self):
        print(f"{self.colors['info']}Waiting for cursor movement in Neovim...{self.colors['reset']}")
    
    def display_file_info(self, data):
        if "current_file" in data:
            file_name = data['current_file']
            line = data.get('cursor_line', 0)
            col = data.get('cursor_col', 0)
            
            print(f"{self.colors['file']}📄 Current File: {file_name}{self.colors['reset']}")
            print(f"   Line {line}, Column {col}")
            print()
    
    def display_documentation(self, hover_data):
        if not hover_data:
            return
            
        print(f"{self.colors['documentation']}📖 Documentation:{self.colors['reset']}")
        for line in hover_data:
            print(f"   {line}")
        print()
    
    def display_definition(self, def_data):
        if not def_data:
            return
            
        file_name = def_data['file']
        line = def_data['line']
        char = def_data['character']
        
        print(f"{self.colors['definition']}📍 Defined in:{self.colors['reset']}")
        print(f"   {file_name}:{line}:{char}")
        print()
    
    def display_references(self, count, references):
        if count is None:
            return
            
        ref_text = "reference" if count == 1 else "references"
        print(f"{self.colors['references']}🔗 {count} {ref_text} found:{self.colors['reset']}")
        
        if references:
            for ref in references:
                print(f"{self.colors['reference_item']}   • {ref}{self.colors['reset']}")
        print()
    
    def display_no_info(self):
        print(f"{self.colors['info']}No additional context information available{self.colors['reset']}")
    
    def display_content(self, content_json):
        try:
            data = json.loads(content_json) if content_json.strip() else {}
        except json.JSONDecodeError:
            data = {"error": "Invalid JSON received"}
        
        self.clear_screen()
        self.print_header()
        
        if "error" in data:
            self.display_error(data['error'])
        elif not data:
            self.display_waiting()
        else:
            self.display_file_info(data)
            
            # Display all available information
            info_displayed = False
            
            if "hover" in data and data["hover"]:
                self.display_documentation(data["hover"])
                info_displayed = True
            
            if "definition_location" in data:
                self.display_definition(data["definition_location"])
                info_displayed = True
            
            if "references_count" in data:
                self.display_references(
                    data["references_count"], 
                    data.get("references", [])
                )
                info_displayed = True
            
            if not info_displayed:
                self.display_no_info()
        
        self.print_footer()
        sys.stdout.flush()

def main():
    display = ContextDisplay()
    
    try:
        for line in sys.stdin:
            if line.strip():
                display.display_content(line.strip())
    except KeyboardInterrupt:
        pass
    except Exception as e:
        display.clear_screen()
        display.print_header()
        display.display_error(f"Display error: {e}")
        display.print_footer()

if __name__ == "__main__":
    main()
]]
end

return M
