-- .luacheckrc - Configuration for luacheck

-- Neovim globals
globals = {
  "vim",
}

-- Neovim API patterns
read_globals = {
  "vim",
}

-- Standard library
std = "max"

-- Exclude files/directories
exclude_files = {
  "lua_modules",
  ".luarocks",
  "**/*_spec.lua",
  "**/spec/**",
}

-- Warning codes to ignore
ignore = {
  "122", -- Setting read-only field
  "212", -- Unused argument (common in callbacks)
  "213", -- Unused loop variable
  "214", -- Used variable with unused hint
  "411", -- Redefining local variable
  "412", -- Redefining argument
  "421", -- Shadowing local variable
  "422", -- Shadowing argument
  "423", -- Shadowing loop variable
  "431", -- Shadowing upvalue
  "432", -- Shadowing upvalue argument
  "433", -- Shadowing upvalue loop variable
}

-- Files with specific configurations
files["lua/hoverfloat/init.lua"] = {
  -- Allow globals commonly used in init files
  globals = {
    "vim",
  },
}

files["lua/hoverfloat/lsp_collector.lua"] = {
  -- LSP-specific globals
  globals = {
    "vim",
  },
}

files["lua/hoverfloat/socket_client.lua"] = {
  -- Socket-specific globals
  globals = {
    "vim",
  },
}

-- Development/test files
files["dev/**/*.lua"] = {
  -- More relaxed rules for dev files
  ignore = {
    "111", -- Setting non-standard global variable
    "112", -- Mutating non-standard global variable
    "113", -- Accessing undefined variable
  },
}

-- Example configuration files
files["examples/**/*.lua"] = {
  -- Allow example-specific patterns
  ignore = {
    "111", -- Setting non-standard global variable
    "631", -- Line is too long
  },
}
