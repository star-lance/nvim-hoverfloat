-- lua/hoverfloat/core/performance.lua - Simple performance coordinator (refactored)
local M = {}

-- Import the focused modules
local metrics = require('hoverfloat.core.metrics')
local analyzer = require('hoverfloat.core.analyzer')
local monitor = require('hoverfloat.core.monitor')

-- Public API - exact same functions as original (delegated to metrics)
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

-- Public API - analysis functions (delegated to analyzer)
function M.get_cache_hit_rate()
  local stats = metrics.get_stats()
  return analyzer.get_cache_hit_rate(stats)
end

function M.get_error_rate()
  local stats = metrics.get_stats()
  return analyzer.get_error_rate(stats)
end

function M.analyze_performance()
  local stats = metrics.get_stats()
  return analyzer.analyze_performance(stats)
end

-- Public API - get stats (delegated to metrics)
function M.get_stats()
  local stats = metrics.get_stats()
  
  -- Add calculated rates for backward compatibility
  stats.cache_hit_rate = analyzer.get_cache_hit_rate(stats)
  stats.error_rate = analyzer.get_error_rate(stats)
  
  return stats
end

-- Public API - report generation (original function, simplified)
function M.get_performance_report()
  local stats = metrics.get_stats()

  local report = {
    "=== Performance Report ===",
    string.format("Total Requests: %d", stats.total_requests),
    string.format("Cache Hit Rate: %.1f%%", analyzer.get_cache_hit_rate(stats) * 100),
    string.format("Error Rate: %.1f%%", analyzer.get_error_rate(stats) * 100),
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

-- Public API - monitoring (delegated to monitor)
function M.start_monitoring()
  monitor.start_monitoring(metrics.get_stats, analyzer)
end

function M.stop_monitoring()
  monitor.stop_monitoring()
end

function M.check_performance_warnings()
  local stats = metrics.get_stats()
  monitor.check_performance_warnings(stats, analyzer)
end

-- Public API - reset (delegated to metrics)
function M.reset_stats()
  metrics.reset_stats()
end

return M
