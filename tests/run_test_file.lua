-- tests/run_test_file.lua - Direct test runner that bypasses plenary commands

local file_to_test = arg and arg[1]
if not file_to_test then
  error("Usage: nvim -l run_test_file.lua <test_file.lua>")
end

-- Load plenary test framework
local ok, busted = pcall(require, 'plenary.busted')
if not ok then
  error("plenary.nvim not found. Please install it first.")
end

-- Print test file being run
print("Running tests from: " .. file_to_test)

-- Run the test file directly
local success, error_msg = pcall(function()
  busted.run(file_to_test)
end)

if not success then
  print("Test failed with error: " .. tostring(error_msg))
  os.exit(1)
else
  print("Tests completed successfully")
  os.exit(0)
end
