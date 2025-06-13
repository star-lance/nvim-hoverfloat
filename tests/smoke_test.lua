-- tests/smoke_test.lua - Basic smoke test to verify environment

-- This will work with either plenary or the simple runner
local function describe(name, func)
  if _G.describe then
    _G.describe(name, func)
  else
    print("📝 " .. name)
    func()
  end
end

local function it(name, func)
  if _G.it then
    _G.it(name, func)
  else
    local ok, err = pcall(func)
    if ok then
      print("  ✅ " .. name)
    else
      print("  ❌ " .. name .. ": " .. tostring(err))
      error("Test failed: " .. name)
    end
  end
end

-- Use either plenary assert or our simple one
local assert = _G.assert or require('luassert')

-- Basic environment smoke test
describe('Test Environment', function()
  it('should have working assertions', function()
    assert.equals(2, 1 + 1)
    assert.is_true(true)
    assert.is_false(false)
  end)

  it('should be able to create and manipulate tables', function()
    local test_table = { a = 1, b = 2 }
    assert.is_table(test_table)
    assert.equals(1, test_table.a)
    assert.equals(2, test_table.b)
  end)

  it('should have basic lua functions available', function()
    assert.is_function(require)
    assert.is_function(pairs)
    assert.is_function(ipairs)
    assert.is_function(type)
  end)
end)

print("✅ Smoke test completed")
