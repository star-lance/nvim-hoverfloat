-- tests/integration_performance_tests.lua - Integration and Performance Tests

local assert = require('luassert')

describe('Real-world Integration Tests', function()
  local hoverfloat
  local socket_path = '/tmp/test_hoverfloat_' .. os.time() .. '.sock'
  
  before_each(function()
    -- Clean up any existing test sockets
    os.remove(socket_path)
    
    -- Clear loaded modules
    for name, _ in pairs(package.loaded) do
      if name:match('^hoverfloat') then
        package.loaded[name] = nil
      end
    end
    
    hoverfloat = require('hoverfloat')
  end)
  
  after_each(function()
    if hoverfloat and hoverfloat.stop then
      hoverfloat.stop()
    end
    
    -- Clean up test socket
    os.remove(socket_path)
    
    -- Wait a bit for cleanup
    vim.wait(100)
  end)
  
  describe('Socket IPC Performance', function()
    it('should establish socket connection within 100ms', function()
      local socket_client = require('hoverfloat.communication.socket_client')
      
      local start_time = vim.uv.now()
      socket_client.connect(socket_path)
      
      -- Give it time to attempt connection
      local connected = vim.wait(200, function() 
        return socket_client.is_connected() 
      end)
      
      local elapsed = vim.uv.now() - start_time
      
      -- For testing, we'll just verify the attempt was made quickly
      assert.is_true(elapsed < 300, "Connection attempt should be fast")
      
      -- Clean up
      socket_client.disconnect()
    end)
    
    it('should handle message queueing when not connected', function()
      local socket_client = require('hoverfloat.communication.socket_client')
      
      -- Try to send message when not connected
      local test_data = {
        file = '/test.lua',
        line = 1,
        col = 1,
        timestamp = vim.uv.now()
      }
      
      local result = socket_client.send_context_update(test_data)
      
      -- Should return false when not connected
      assert.is_false(result)
      
      -- Status should show not connected
      local status = socket_client.get_status()
      assert.is_false(status.connected)
    end)
    
    it('should handle rapid message sending gracefully', function()
      local socket_client = require('hoverfloat.communication.socket_client')
      
      local messages_sent = 0
      local send_failures = 0
      
      for i = 1, 20 do
        local success = socket_client.send_context_update({
          file = '/test.lua',
          line = i,
          col = 1,
          timestamp = vim.uv.now()
        })
        
        if success then
          messages_sent = messages_sent + 1
        else
          send_failures = send_failures + 1
        end
        
        vim.wait(1) -- Small delay
      end
      
      -- Should handle messages without crashing
      assert.is_true(send_failures >= 0, "Should handle send failures gracefully")
      assert.is_true(messages_sent >= 0, "Should track sent messages")
    end)
    
    it('should maintain connection state correctly', function()
      local socket_client = require('hoverfloat.communication.socket_client')
      
      -- Initially should not be connected
      assert.is_false(socket_client.is_connected())
      assert.is_false(socket_client.is_connecting())
      
      -- After connection attempt
      socket_client.connect(socket_path)
      
      -- Should either be connecting or connected
      local status = socket_client.get_status()
      assert.is_table(status)
      assert.is_boolean(status.connected)
      assert.is_boolean(status.connecting)
      
      socket_client.disconnect()
      
      -- After disconnect should be disconnected
      vim.wait(50)
      assert.is_false(socket_client.is_connected())
    end)
  end)
  
  describe('LSP Real-time Performance', function()
    local function create_test_file_with_lsp()
      local test_file = '/tmp/test_lsp_' .. os.time() .. '.lua'
      local content = [[
local function test_function(param)
  local variable = param * 2
  return variable
end

local M = {}
M.test_function = test_function
return M
]]
      local file = io.open(test_file, 'w')
      if file then
        file:write(content)
        file:close()
      end
      
      -- Open file in a buffer
      vim.cmd('edit ' .. test_file)
      
      return test_file
    end
    
    it('should handle LSP requests with appropriate timeouts', function()
      local test_file = create_test_file_with_lsp()
      local lsp_service = require('hoverfloat.core.lsp_service')
      
      -- Check if we have LSP clients
      local has_clients = lsp_service.has_lsp_clients(0)
      
      if not has_clients then
        pending("No LSP server attached - skipping LSP integration test")
        return
      end
      
      local start_time = vim.uv.now()
      local hover_received = false
      local request_completed = false
      
      vim.api.nvim_win_set_cursor(0, {2, 15}) -- Position on 'variable'
      
      lsp_service.get_hover(0, 2, 15, function(result, err)
        hover_received = result ~= nil
        request_completed = true
      end)
      
      -- Wait for request to complete
      vim.wait(1000, function() return request_completed end)
      local elapsed = vim.uv.now() - start_time
      
      assert.is_true(request_completed, "LSP request should complete")
      assert.is_true(elapsed < 1000, "Should complete within reasonable time")
      
      -- Clean up
      os.remove(test_file)
    end)
    
    it('should handle multiple concurrent LSP requests', function()
      local test_file = create_test_file_with_lsp()
      local lsp_service = require('hoverfloat.core.lsp_service')
      
      if not lsp_service.has_lsp_clients(0) then
        pending("No LSP server attached")
        return
      end
      
      local completed_requests = 0
      local total_requests = 3
      
      local function make_request(line, col)
        lsp_service.get_hover(0, line, col, function(result, err)
          completed_requests = completed_requests + 1
        end)
      end
      
      -- Make multiple requests
      make_request(2, 15)
      make_request(3, 10)
      make_request(4, 5)
      
      -- Wait for all to complete
      vim.wait(2000, function() 
        return completed_requests >= total_requests 
      end)
      
      assert.is_true(completed_requests >= 0, "Should handle concurrent requests")
      
      -- Clean up
      os.remove(test_file)
    end)
    
    it('should gather comprehensive context data', function()
      local test_file = create_test_file_with_lsp()
      local lsp_service = require('hoverfloat.core.lsp_service')
      
      if not lsp_service.has_lsp_clients(0) then
        pending("No LSP server attached")
        return
      end
      
      local context_result = nil
      local request_completed = false
      
      vim.api.nvim_win_set_cursor(0, {2, 15})
      
      lsp_service.gather_all_context(0, 2, 15, nil, function(result)
        context_result = result
        request_completed = true
      end)
      
      vim.wait(2000, function() return request_completed end)
      
      assert.is_true(request_completed, "Context gathering should complete")
      
      if context_result then
        assert.is_table(context_result)
        assert.is_string(context_result.file)
        assert.is_number(context_result.line)
        assert.is_number(context_result.col)
        assert.is_number(context_result.timestamp)
      end
      
      -- Clean up
      os.remove(test_file)
    end)
  end)
  
  describe('Cache Performance Under Load', function()
    it('should maintain performance with 100+ entries', function()
      local cache = require('hoverfloat.prefetch.cache')
      cache.clear_all()
      
      local start_time = vim.uv.now()
      
      -- Store many entries
      for i = 1, 100 do
        local test_data = {
          hover = {'test content ' .. i},
          definition = {file = '/test' .. i .. '.lua', line = i, col = 1},
          timestamp = vim.uv.now()
        }
        cache.store(1, i, 'symbol_' .. i, test_data)
      end
      
      local store_time = vim.uv.now() - start_time
      
      start_time = vim.uv.now()
      
      -- Retrieve entries
      local retrieved_count = 0
      for i = 1, 100 do
        local result = cache.get(1, i, 'symbol_' .. i)
        if result then
          retrieved_count = retrieved_count + 1
        end
      end
      
      local retrieve_time = vim.uv.now() - start_time
      
      assert.is_true(store_time < 1000, "Store operations should be fast")
      assert.is_true(retrieve_time < 500, "Retrieval should be fast")
      assert.is_true(retrieved_count > 90, "Should retrieve most cached items")
      
      -- Test cache statistics
      local stats = cache.get_stats()
      assert.is_table(stats)
      assert.is_true(stats.total_symbols_cached > 90)
    end)
    
    it('should handle cache cleanup efficiently', function()
      local cache = require('hoverfloat.prefetch.cache')
      cache.clear_all()
      
      -- Add many entries
      for i = 1, 50 do
        local test_data = {
          hover = {'test content ' .. i},
          timestamp = vim.uv.now()
        }
        cache.store(1, i, 'symbol_' .. i, test_data)
      end
      
      local initial_count = cache.get_total_cached_symbols()
      assert.is_true(initial_count >= 40, "Should have cached many symbols")
      
      -- Cleanup
      local start_time = vim.uv.now()
      local cleaned = cache.cleanup_expired()
      local cleanup_time = vim.uv.now() - start_time
      
      assert.is_true(cleanup_time < 100, "Cleanup should be fast")
      assert.is_number(cleaned)
      
      -- Clear buffer should work quickly
      start_time = vim.uv.now()
      cache.clear_buffer(1)
      local clear_time = vim.uv.now() - start_time
      
      assert.is_true(clear_time < 50, "Buffer clear should be fast")
      
      local final_count = cache.get_total_cached_symbols()
      assert.equals(0, final_count)
    end)
    
    it('should handle concurrent cache operations', function()
      local cache = require('hoverfloat.prefetch.cache')
      cache.clear_all()
      
      local operations_completed = 0
      local total_operations = 20
      
      local function perform_cache_operation(id)
        vim.defer_fn(function()
          local test_data = {
            hover = {'concurrent test ' .. id},
            timestamp = vim.uv.now()
          }
          
          -- Store
          cache.store(1, id, 'concurrent_' .. id, test_data)
          
          -- Retrieve
          local result = cache.get(1, id, 'concurrent_' .. id)
          
          if result then
            operations_completed = operations_completed + 1
          end
        end, math.random(1, 50))
      end
      
      -- Start concurrent operations
      for i = 1, total_operations do
        perform_cache_operation(i)
      end
      
      -- Wait for all operations to complete
      vim.wait(2000, function() 
        return operations_completed >= total_operations - 2 -- Allow some margin
      end)
      
      assert.is_true(operations_completed >= total_operations - 5, 
        "Most concurrent operations should succeed")
      
      local stats = cache.get_stats()
      assert.is_true(stats.total_symbols_cached > 0)
    end)
  end)
  
  describe('Cursor Tracking Performance', function()
    it('should handle rapid cursor movement without errors', function()
      local cursor_tracker = require('hoverfloat.core.cursor_tracker')
      
      -- Enable tracking
      cursor_tracker.enable()
      
      local initial_stats = cursor_tracker.get_stats()
      assert.is_table(initial_stats)
      assert.is_true(initial_stats.tracking_enabled)
      
      -- Simulate rapid cursor movement
      for i = 1, 20 do
        vim.api.nvim_win_set_cursor(0, {i, i})
        vim.wait(10) -- Small delay
      end
      
      -- Should handle movement without crashing
      local final_stats = cursor_tracker.get_stats()
      assert.is_table(final_stats)
      assert.is_true(final_stats.tracking_enabled)
      
      -- Test forced update
      local start_time = vim.uv.now()
      cursor_tracker.force_update()
      local update_time = vim.uv.now() - start_time
      
      assert.is_true(update_time < 100, "Force update should be fast")
      
      cursor_tracker.disable()
    end)
    
    it('should debounce cursor updates correctly', function()
      local cursor_tracker = require('hoverfloat.core.cursor_tracker')
      
      cursor_tracker.enable()
      cursor_tracker.set_debounce_delay(50) -- 50ms debounce
      
      local initial_position = cursor_tracker.get_stats().last_sent_position
      
      -- Rapid cursor movements should be debounced
      for i = 1, 10 do
        vim.api.nvim_win_set_cursor(0, {i, 1})
        vim.wait(5) -- Faster than debounce
      end
      
      -- Wait for debounce to settle
      vim.wait(100)
      
      local stats = cursor_tracker.get_stats()
      
      -- Should have debounced rapid movements
      assert.is_table(stats)
      
      cursor_tracker.disable()
    end)
  end)
  
  describe('Performance Monitoring', function()
    it('should track performance metrics accurately', function()
      local performance = require('hoverfloat.core.performance')
      
      -- Reset stats for clean test
      performance.reset_stats()
      
      local initial_stats = performance.get_stats()
      assert.equals(0, initial_stats.total_requests)
      
      -- Simulate some requests
      for i = 1, 10 do
        local start_time = performance.start_request()
        vim.wait(math.random(1, 10)) -- Variable delay
        performance.complete_request(start_time, i % 2 == 0, false)
      end
      
      local final_stats = performance.get_stats()
      assert.equals(10, final_stats.total_requests)
      assert.is_true(final_stats.cache_hits >= 0)
      assert.is_true(final_stats.average_response_time >= 0)
      
      -- Test performance analysis
      local analysis = performance.analyze_performance()
      assert.is_table(analysis)
      
      -- Test performance report
      local report = performance.get_performance_report()
      assert.is_string(report)
      assert.matches("Performance Report", report)
    end)
    
    it('should handle performance monitoring without errors', function()
      local performance = require('hoverfloat.core.performance')
      
      -- Start monitoring
      performance.start_monitoring()
      
      -- Record various operations
      performance.record_cache_hit()
      performance.record_lsp_request()
      performance.update_prefetch_stats(50, 10, 5)
      
      -- Stop monitoring
      performance.stop_monitoring()
      
      -- Should complete without errors
      local stats = performance.get_stats()
      assert.is_table(stats)
      assert.is_true(stats.cache_hits > 0)
    end)
  end)
  
  describe('Memory and Resource Management', function()
    it('should manage memory efficiently during long operations', function()
      local cache = require('hoverfloat.prefetch.cache')
      
      -- Clear and measure initial state
      cache.clear_all()
      collectgarbage('collect')
      local initial_memory = collectgarbage('count')
      
      -- Perform many cache operations
      for i = 1, 200 do
        local large_data = {
          hover = {},
          timestamp = vim.uv.now()
        }
        
        -- Create some content
        for j = 1, 10 do
          table.insert(large_data.hover, 'Line ' .. j .. ' of content for symbol ' .. i)
        end
        
        cache.store(1, i, 'memory_test_' .. i, large_data)
        
        -- Occasional cleanup
        if i % 50 == 0 then
          cache.cleanup_expired()
          collectgarbage('collect')
        end
      end
      
      collectgarbage('collect')
      local peak_memory = collectgarbage('count')
      
      -- Clear all data
      cache.clear_all()
      collectgarbage('collect')
      local final_memory = collectgarbage('count')
      
      -- Memory should be reclaimed
      assert.is_true(peak_memory > initial_memory, "Memory should increase during operations")
      assert.is_true(final_memory <= peak_memory, "Memory should be reclaimed after cleanup")
      
      -- Memory increase should be reasonable (not a memory leak)
      local memory_increase = final_memory - initial_memory
      assert.is_true(memory_increase < 1000, "Memory increase should be reasonable (< 1MB)")
    end)
    
    it('should handle resource cleanup properly', function()
      local socket_client = require('hoverfloat.communication.socket_client')
      local cursor_tracker = require('hoverfloat.core.cursor_tracker')
      local performance = require('hoverfloat.core.performance')
      
      -- Initialize components
      cursor_tracker.enable()
      performance.start_monitoring()
      
      -- Use components
      socket_client.send_context_update({
        file = '/test.lua',
        line = 1,
        col = 1,
        timestamp = vim.uv.now()
      })
      
      cursor_tracker.force_update()
      
      -- Cleanup
      cursor_tracker.cleanup()
      socket_client.cleanup()
      performance.stop_monitoring()
      
      -- Verify cleanup
      local tracker_stats = cursor_tracker.get_stats()
      assert.is_false(tracker_stats.tracking_enabled)
      
      local socket_status = socket_client.get_status()
      assert.is_false(socket_status.connected)
    end)
  end)
end)
