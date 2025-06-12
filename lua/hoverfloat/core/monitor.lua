-- lua/hoverfloat/core/monitor.lua - Simple background monitoring (from original)
local M = {}

-- Monitor state (simplified from original)
local monitor_timer = nil

-- Check performance warnings (original function logic)
function M.check_performance_warnings(stats, analyzer)
  local logger = require('hoverfloat.utils.logger')
  local warnings = analyzer.analyze_performance(stats)

  for _, warning in ipairs(warnings) do
    logger.plugin("warn", "Performance: " .. warning)
  end
end

-- Start performance monitoring (original function with hardcoded interval)
function M.start_monitoring(get_stats_fn, analyzer)
  local interval_ms = 30000 -- 30 seconds (from original)

  if monitor_timer then
    monitor_timer:close()
  end

  monitor_timer = vim.loop.new_timer()
  if monitor_timer then
    monitor_timer:start(interval_ms, interval_ms, vim.schedule_wrap(function()
      local stats = get_stats_fn()
      M.check_performance_warnings(stats, analyzer)
    end))
  end
end

-- Stop performance monitoring (original function)
function M.stop_monitoring()
  if monitor_timer then
    monitor_timer:close()
    monitor_timer = nil
  end
end

return M
