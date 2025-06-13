print("🔍 Debug test starting...")

-- Test that plenary is working
local assert = require('luassert')
print("✅ luassert loaded")

-- Test basic assertions
describe('Basic Environment Test', function()
  it('should have working assertions', function()
    assert.equals(2, 1 + 1)
    assert.is_true(true)
    assert.is_false(false)
    print("✅ Basic assertions work")
  end)

  it('should be able to create tables', function()
    local test_table = { a = 1, b = 2 }
    assert.is_table(test_table)
    assert.equals(1, test_table.a)
    print("✅ Table operations work")
  end)
end)

-- Test minimal vim mock
describe('Minimal Vim Mock Test', function()
  it('should create basic vim mock', function()
    _G.vim = {
      uv = {
        now = function() return 12345 end
      },
      fn = {
        expand = function() return "test" end
      }
    }

    assert.equals(12345, vim.uv.now())
    assert.equals("test", vim.fn.expand())
    print("✅ Basic vim mock works")
  end)
end)

print("🔍 Debug test completed successfully!")
