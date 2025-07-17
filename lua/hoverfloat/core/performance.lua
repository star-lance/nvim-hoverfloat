-- lua/hoverfloat/core/performance.lua - Self-contained performance module
local M = {}

-- Import only the core metrics module to avoid circular dependencies
local metrics = require('hoverfloat.core.metrics')

-- Analysis functions (inline to avoid circular dependencies)
local function get_cache_hit_rate(stats)
  if stats.total_requests == 0 then
    return 0
  end
  return stats.cache_hits / stats.total_requests
end

local function get_error_rate(stats)
  if stats.total_requests == 0 then
    return 0
  end
  return stats.errors / stats.total_requests
end

local function analyze_performance(stats)
  local analysis = {}

  -- Cache performance analysis
  local cache_hit_rate = get_cache_hit_rate(stats)
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
  local error_rate = get_error_rate(stats)
  if error_rate > 0.1 then
    table.insert(analysis, "High error rate - check LSP configuration")
  end

  -- Request rate analysis
  if stats.requests_per_second > 10 then
    table.insert(analysis, "High request rate - consider increasing debounce delay")
  end

  return analysis
end

-- Monitoring state
local monitor_timer = nil

local function check_performance_warnings()
  local logger = require('hoverfloat.utils.logger')
  local stats = M.get_stats()
  local warnings = analyze_performance(stats)

  for _, warning in ipairs(warnings) do
    logger.plugin("warn", "Performance: " .. warning)
  end
end

-- Public API - delegate to metrics
function M.start_request()
  return metrics.start_request()
end

function M.complete_request(start_time, was_cache_hit, had_error)
  return metrics.complete_request(start_time, was_cache_hit, had_error)
end

function M.record_cache_hit()
  metrics.record_cache_hit()
end

function M.record_lsp_request()
  metrics.record_lsp_request()
end

function M.record_error()
  metrics.record_error()
end

function M.update_prefetch_stats(symbols_cached, prefetch_requests, queue_size)
  metrics.update_prefetch_stats(symbols_cached, prefetch_requests, queue_size)
end

-- Public API - analysis functions
function M.get_cache_hit_rate()
  local stats = metrics.get_stats()
  return get_cache_hit_rate(stats)
end

function M.get_error_rate()
  local stats = metrics.get_stats()
  return get_error_rate(stats)
end

function M.analyze_performance()
  local stats = metrics.get_stats()
  return analyze_performance(stats)
end

-- Public API - get stats with calculated rates
function M.get_stats()
  local stats = metrics.get_stats()
  
  -- Add calculated rates for backward compatibility
  stats.cache_hit_rate = get_cache_hit_rate(stats)
  stats.error_rate = get_error_rate(stats)
  
  return stats
end

-- Public API - report generation
function M.get_performance_report()
  local stats = M.get_stats()

  local report = {
    "=== Performance Report ===",
    string.format("Total Requests: %d", stats.total_requests),
    string.format("Cache Hit Rate: %.1f%%", stats.cache_hit_rate * 100),
    string.format("Error Rate: %.1f%%", stats.error_rate * 100),
    string.format("Average Response Time: %.2fms", stats.average_response_time),
    string.format("Requests/Second: %.2f", stats.requests_per_second),
    "",
    "=== Cache Performance ===",
    string.format("Cache Hits: %d", stats.cache_hits),
    string.format("LSP Requests: %d", stats.lsp_requests),
    string.format("Symbols Cached: %d", stats.prefetch_stats.symbols_cached),
    "",
    "=== Session Info ===",
    string.format("Uptime: %.2fs", stats.uptime_ms / 1000),
  }

  return table.concat(report, "\n")
end

-- Public API - monitoring
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

-- Public API - reset
function M.reset_stats()
  metrics.reset_stats()
end

return M
