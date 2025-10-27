-- performance_profiler.lua
-- Performance profiling and analysis tool for AseVoxel rendering pipeline

local performanceProfiler = {}

-- Profiling data storage
performanceProfiler._profiles = {}
performanceProfiler._activeProfile = nil
performanceProfiler._samples = {}
performanceProfiler._maxSamples = 50

-- Timing utilities
local function nowMs()
  return os.clock() * 1000
end

-- Statistical calculations
local function calculateStats(samples)
  if #samples == 0 then
    return {count=0, mean=0, median=0, min=0, max=0, p75=0, p90=0, p95=0, p99=0}
  end
  
  -- Sort for percentile calculations
  local sorted = {}
  for i, v in ipairs(samples) do sorted[i] = v end
  table.sort(sorted)
  
  -- Calculate mean
  local sum = 0
  for _, v in ipairs(sorted) do sum = sum + v end
  local mean = sum / #sorted
  
  -- Calculate median
  local n = #sorted
  local median
  if n % 2 == 1 then
    median = sorted[(n+1)/2]
  else
    median = (sorted[n/2] + sorted[n/2+1]) / 2
  end
  
  -- Calculate percentiles
  local function percentile(p)
    local idx = math.ceil(n * p)
    if idx < 1 then idx = 1 end
    if idx > n then idx = n end
    return sorted[idx]
  end
  
  return {
    count = n,
    mean = mean,
    median = median,
    min = sorted[1],
    max = sorted[n],
    p75 = percentile(0.75),
    p90 = percentile(0.90),
    p95 = percentile(0.95),
    p99 = percentile(0.99),
    sum = sum
  }
end

-- Start a new profiling session
function performanceProfiler.startProfile(name)
  name = name or "default"
  
  if not performanceProfiler._profiles[name] then
    performanceProfiler._profiles[name] = {
      sections = {},
      timestamps = {},
      startTime = nowMs()
    }
  end
  
  performanceProfiler._activeProfile = name
  performanceProfiler._profiles[name].sessionStart = nowMs()
  
  return name
end

-- Mark the start of a timed section
function performanceProfiler.mark(sectionName)
  local profile = performanceProfiler._profiles[performanceProfiler._activeProfile]
  if not profile then return end
  
  profile.timestamps[sectionName] = nowMs()
end

-- End a timed section and record duration
function performanceProfiler.measure(sectionName)
  local profile = performanceProfiler._profiles[performanceProfiler._activeProfile]
  if not profile or not profile.timestamps[sectionName] then return end
  
  local duration = nowMs() - profile.timestamps[sectionName]
  
  if not profile.sections[sectionName] then
    profile.sections[sectionName] = {}
  end
  
  table.insert(profile.sections[sectionName], duration)
  
  -- Limit sample count
  local samples = profile.sections[sectionName]
  while #samples > performanceProfiler._maxSamples do
    table.remove(samples, 1)
  end
  
  profile.timestamps[sectionName] = nil
  
  return duration
end

-- Convenience function: mark and measure in one call
function performanceProfiler.timed(sectionName, func)
  performanceProfiler.mark(sectionName)
  local result = func()
  performanceProfiler.measure(sectionName)
  return result
end

-- End profiling session
function performanceProfiler.endProfile()
  local profile = performanceProfiler._profiles[performanceProfiler._activeProfile]
  if profile then
    profile.sessionEnd = nowMs()
    profile.sessionDuration = profile.sessionEnd - profile.sessionStart
  end
  performanceProfiler._activeProfile = nil
end

-- Get statistics for a specific section
function performanceProfiler.getStats(profileName, sectionName)
  profileName = profileName or performanceProfiler._activeProfile or "default"
  local profile = performanceProfiler._profiles[profileName]
  
  if not profile then return nil end
  
  if sectionName then
    local samples = profile.sections[sectionName]
    if not samples then return nil end
    return calculateStats(samples)
  else
    -- Return all sections
    local allStats = {}
    for name, samples in pairs(profile.sections) do
      allStats[name] = calculateStats(samples)
    end
    return allStats
  end
end

-- Clear all profiling data
function performanceProfiler.clear(profileName)
  if profileName then
    performanceProfiler._profiles[profileName] = nil
  else
    performanceProfiler._profiles = {}
  end
end

-- Generate a formatted report
function performanceProfiler.generateReport(profileName)
  profileName = profileName or performanceProfiler._activeProfile or "default"
  local profile = performanceProfiler._profiles[profileName]
  
  if not profile then
    return "No profile data for: " .. profileName
  end
  
  local lines = {}
  table.insert(lines, "=== Performance Profile: " .. profileName .. " ===")
  table.insert(lines, "")
  
  -- Sort sections by mean time (descending)
  local sections = {}
  for name, samples in pairs(profile.sections) do
    local stats = calculateStats(samples)
    table.insert(sections, {name=name, stats=stats})
  end
  table.sort(sections, function(a,b) return a.stats.mean > b.stats.mean end)
  
  -- Calculate total time
  local totalTime = 0
  for _, section in ipairs(sections) do
    totalTime = totalTime + section.stats.sum
  end
  
  table.insert(lines, string.format("%-30s %8s %8s %8s %8s %8s %8s %8s", 
    "Section", "Count", "Mean", "Median", "Min", "Max", "P95", "%Total"))
  table.insert(lines, string.rep("-", 100))
  
  for _, section in ipairs(sections) do
    local s = section.stats
    local pct = (s.sum / totalTime) * 100
    table.insert(lines, string.format("%-30s %8d %7.2fms %7.2fms %7.2fms %7.2fms %7.2fms %6.1f%%",
      section.name,
      s.count,
      s.mean,
      s.median,
      s.min,
      s.max,
      s.p95,
      pct
    ))
  end
  
  table.insert(lines, string.rep("-", 100))
  table.insert(lines, string.format("Total profiled time: %.2fms (avg per sample)", totalTime / (sections[1] and sections[1].stats.count or 1)))
  
  return table.concat(lines, "\n")
end

-- Print report to console
function performanceProfiler.printReport(profileName)
  print(performanceProfiler.generateReport(profileName))
end

-- Export data for external analysis
function performanceProfiler.exportData(profileName)
  profileName = profileName or performanceProfiler._activeProfile or "default"
  local profile = performanceProfiler._profiles[profileName]
  
  if not profile then return nil end
  
  local data = {}
  for name, samples in pairs(profile.sections) do
    data[name] = {
      samples = samples,
      stats = calculateStats(samples)
    }
  end
  
  return data
end

-- Get quick summary for display in UI
function performanceProfiler.getQuickSummary(profileName)
  profileName = profileName or performanceProfiler._activeProfile or "default"
  local allStats = performanceProfiler.getStats(profileName)
  
  if not allStats then return "No profiling data" end
  
  -- Find the most expensive operations
  local sorted = {}
  for name, stats in pairs(allStats) do
    table.insert(sorted, {name=name, mean=stats.mean})
  end
  table.sort(sorted, function(a,b) return a.mean > b.mean end)
  
  local lines = {}
  for i = 1, math.min(5, #sorted) do
    table.insert(lines, string.format("%s: %.2fms", sorted[i].name, sorted[i].mean))
  end
  
  return table.concat(lines, "\n")
end

-- Alias for consistency with UI
performanceProfiler.clearProfile = performanceProfiler.clear

return performanceProfiler

