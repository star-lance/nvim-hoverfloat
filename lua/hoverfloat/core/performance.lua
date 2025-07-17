-- lua/hoverfloat/core/performance.lua - Completely self-contained performance module
local M = {}

-- Performance state - everything in one place to avoid circular dependencies
local stats = {
  total_requests = 0,
  cache_hits = 0,
  lsp_requests = 0,
  average_response_time = 0,
  response_times = {}, -- circular buffer for recent times
  errors = 0,
  prefetch_stats = {
    symbols_cached = 0,
    prefetch_requests = 0,
    queue_size = 0,
  },
  session_start = vim.uv.now(),
}

-- Circular buffer for response times (keep last 100)
local MAX_RESPONSE_TIMES = 100
local response_time_index = 1

-- Monitoring state
local monitor_timer = nil

-- Record a request start
function M.start_request()
  stats.total_requests = stats.total_requests + 1
  return vim.uv.now()
end

-- Record a request completion
function M.complete_request(start_time, was_cache_hit, had_error)
  local end_time = vim.uv.now()
  local response_time = end_time - start_time

  -- Record response time
  stats.response_times[response_time_index] = response_time
  response_time_index = (response_time_index % MAX_RESPONSE_TIMES) + 1

  -- Update average (simple moving average)
  local total_time = 0
  local count = 0
  for _, time in pairs(stats.response_times) do
    total_time = total_time + time
    count = count + 1
  end
  stats.average_response_time = count > 0 and (total_time / count) or 0

  -- Update counters
  if was_cache_hit then
    stats.cache_hits = stats.cache_hits + 1
  else
    stats.lsp_requests = stats.lsp_requests + 1
  end

  if had_error then
    stats.errors = stats.errors + 1
  end

  return response_time
end

-- Record cache hit
function M.record_cache_hit()
  stats.cache_hits = stats.cache_hits + 1
  stats.total_requests = stats.total_requests + 1
end

-- Record LSP request
function M.record_lsp_request()
  stats.lsp_requests = stats.lsp_requests + 1
end

-- Record error
function M.record_error()
  stats.errors = stats.errors + 1
end

-- Update prefetch statistics
function M.update_prefetch_stats(symbols_cached, prefetch_requests, queue_size)
  stats.prefetch_stats.symbols_cached = symbols_cached or stats.prefetch_stats.symbols_cached
  stats.prefetch_stats.prefetch_requests = prefetch_requests or stats.prefetch_stats.prefetch_requests
  stats.prefetch_stats.queue_size = queue_size or stats.prefetch_stats.queue_size
end

-- Analysis functions (inline to avoid any external dependencies)
function M.get_cache_hit_rate()
  if stats.total_requests == 0 then
    return 0
  end
  return stats.cache_hits / stats.total_requests
end

function M.get_error_rate()
  if stats.total_requests == 0 then
    return 0
  end
  return stats.errors / stats.total_requests
end

function M.analyze_performance()
  local analysis = {}

  -- Cache performance analysis
  local cache_hit_rate = M.get_cache_hit_rate()
  if cache_hit_rate < 0.3 then
    table.insert(analysis, "Low cache hit rate - consider increasing prefetch radius")
  elseif cache_hit_rate > 0.8 then
    table.insert(analysis, "Excellent cache performance")
  end

  -- Response time analysis
  if stats.average_response_time > 100 then
    table.insert(analysis, "High response times - LSP may be slow")
  elseif stats.average_response_time < 10 then
    table.insert(analysis, "Excellent response times")
  end

  -- Error rate analysis
  local error_rate = M.get_error_rate()
  if error_rate > 0.1 then
    table.insert(analysis, "High error rate - check LSP configuration")
  end

  -- Request rate analysis
  local uptime = vim.uv.now() - stats.session_start
  local requests_per_second = stats.total_requests / (uptime / 1000)
  if requests_per_second > 10 then
    table.insert(analysis, "High request rate - consider increasing debounce delay")
  end

  return analysis
end

-- Get current statistics
function M.get_stats()
  local uptime = vim.uv.now() - stats.session_start

  return {
    -- Request statistics
    total_requests = stats.total_requests,
    cache_hits = stats.cache_hits,
    lsp_requests = stats.lsp_requests,
    errors = stats.errors,

    -- Performance metrics
    average_response_time = stats.average_response_time,
    cache_hit_rate = M.get_cache_hit_rate(),
    error_rate = M.get_error_rate(),

    -- Session info
    uptime_ms = uptime,
    requests_per_second = stats.total_requests / (uptime / 1000),

    -- Prefetch statistics
    prefetch_stats = vim.deepcopy(stats.prefetch_stats),

    -- Recent response times for analysis
    recent_response_times = vim.deepcopy(stats.response_times),
  }
end

-- Get performance report
function M.get_performance_report()
  local current_stats = M.get_stats()

  local report = {
    "=== Performance Report ===",
    string.format("Total Requests: %d", current_stats.total_requests),
    string.format("Cache Hit Rate: %.1f%%", current_stats.cache_hit_rate * 100),
    string.format("Error Rate: %.1f%%", current_stats.error_rate * 100),
    string.format("Average Response Time: %.2fms", current_stats.average_response_time),
    string.format("Requests/Second: %.2f", current_stats.requests_per_second),
    "",
    "=== Cache Performance ===",
    string.format("Cache Hits: %d", current_stats.cache_hits),
    string.format("LSP Requests: %d", current_stats.lsp_requests),
    string.format("Symbols Cached: %d", current_stats.prefetch_stats.symbols_cached),
    "",
    "=== Session Info ===",
    string.format("Uptime: %.2fs", current_stats.uptime_ms / 1000),
  }

  return table.concat(report, "\n")
end

-- Performance monitoring with inline implementation
local function check_performance_warnings()
  -- Use pcall to safely require logger (avoid circular deps)
  local ok, logger = pcall(require, 'hoverfloat.utils.logger')
  if ok then
    local warnings = M.analyze_performance()
    for _, warning in ipairs(warnings) do
      logger.plugin("warn", "Performance: " .. warning)
    end
  end
end

function M.start_monitoring()
  local interval_ms = 30000 -- 30 seconds

  if monitor_timer then
    monitor_timer:close()
  end

  monitor_timer = vim.loop.new_timer()
  if monitor_timer then
    monitor_timer:start(interval_ms, interval_ms, vim.schedule_wrap(function()
      check_performance_warnings()
    end))
  end
end

function M.stop_monitoring()
  if monitor_timer then
    monitor_timer:close()
    monitor_timer = nil
  end
end

function M.check_performance_warnings()
  check_performance_warnings()
end

-- Reset statistics
function M.reset_stats()
  stats = {
    total_requests = 0,
    cache_hits = 0,
    lsp_requests = 0,
    average_response_time = 0,
    response_times = {},
    errors = 0,
    prefetch_stats = {
      symbols_cached = 0,
      prefetch_requests = 0,
      queue_size = 0,
    },
    session_start = vim.uv.now(),
  }
  response_time_index = 1
end

return M
