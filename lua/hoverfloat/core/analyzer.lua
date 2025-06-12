-- lua/hoverfloat/core/analyzer.lua - Simple performance analysis (from original)
local M = {}

-- Get cache hit rate (original function)
function M.get_cache_hit_rate(stats)
  if stats.total_requests == 0 then
    return 0
  end
  return stats.cache_hits / stats.total_requests
end

-- Get error rate (original function)
function M.get_error_rate(stats)
  if stats.total_requests == 0 then
    return 0
  end
  return stats.errors / stats.total_requests
end

-- Performance analysis (original function logic)
function M.analyze_performance(stats)
  local analysis = {}

  -- Cache performance analysis (original logic)
  local cache_hit_rate = M.get_cache_hit_rate(stats)
  if cache_hit_rate < 0.3 then
    table.insert(analysis, "Low cache hit rate - consider increasing prefetch radius")
  elseif cache_hit_rate > 0.8 then
    table.insert(analysis, "Excellent cache performance")
  end

  -- Response time analysis (original logic)
  if stats.average_response_time > 100 then
    table.insert(analysis, "High response times - LSP may be slow")
  elseif stats.average_response_time < 10 then
    table.insert(analysis, "Excellent response times")
  end

  -- Error rate analysis (original logic)
  local error_rate = M.get_error_rate(stats)
  if error_rate > 0.1 then
    table.insert(analysis, "High error rate - check LSP configuration")
  end

  -- Request rate analysis (original logic)
  if stats.requests_per_second > 10 then
    table.insert(analysis, "High request rate - consider increasing debounce delay")
  end

  return analysis
end

return M
