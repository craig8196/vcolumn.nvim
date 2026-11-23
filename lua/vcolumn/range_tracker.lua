-- Track ID-associated half-open ranges and report changes to their coverage.
-- Updates are { lo, hi, type }, where type is ADD or REMOVE.
-- Each range has two entries in ilist: { lo, hi, BEG, id } and
-- { hi, lo, END, id }, sorted by their first three fields. This lets scans
-- starting inside a range encounter its end entry. Lists are expected to be
-- small, so insertion and lookup use linear scans.

local M = {}
M.__index = M

-- Create an empty tracker. IDs may be any non-nil, non-false table key.
function M.new()
  local o = {}
  setmetatable(o, M)
  o.idmap = {}
  o.ilist = {}
  return o
end

-- Internal indices for intervals.
local LO = 1
local HI = 2
local OFFSET = 3
local ID = 4

local TYPE = 3

-- Used to adjust for when the end index may come first.
local BEG = 0
local END = 1

-- Export index names.
M.LO = LO
M.HI = HI
M.TYPE = TYPE
-- Export type enum.
M.REMOVE = 0
M.ADD = 1

-- Remove both endpoint entries belonging to an internal range ID.
local function intervallist_remove_by_id(list, id)
  local ilo, ihi
  for i, v in ipairs(list) do
    if id == v[ID] then
      if not ilo then ilo = i
      else ihi = i end
    end
  end
  if ihi then table.remove(list, ihi) end
  if ilo then table.remove(list, ilo) end
end

-- Insert an endpoint in lexicographic order, ignoring its internal ID.
local function intervallist_add(list, interval)
  local function addfn(a, b)
    local i = 1
    local max = OFFSET
    while i <= max do
      if a[i] ~= b[i] then
        return a[i] - b[i]
      end
      i = i + 1
    end
    return 0
  end

  local i = 1
  while i <= #list and addfn(interval, list[i]) > 0 do
    i = i + 1
  end
  table.insert(list, i, interval)
end

-- Recover the bounds from either a beginning or an end entry.
local function low(interval)
  return interval[LO + interval[OFFSET]]
end

local function high(interval)
  return interval[HI - interval[OFFSET]]
end

-- Return up to two pieces of base not covered by subtract.
local function diff(base, subtract)
  if high(base) <= low(subtract) or high(subtract) <= low(base) then
    return { low(base), high(base), BEG }
  end
  local lo, hi
  if low(base) < low(subtract) then
    lo = { low(base), low(subtract), BEG }
  end
  if high(base) > high(subtract) then
    hi = { high(subtract), high(base), BEG }
  end
  return lo, hi
end

-- Find the segments of the interval that ARE NOT covered by the interval list.
-- Endpoint order lets us keep splitting only the last unfinished piece.
local function intervallist_rdiff(list, interval)
  local result = { { interval[LO], interval[HI], BEG } }
  local n = #list
  local i = 1
  while i <= n and list[i][LO] < interval[LO] do
    i = i + 1
  end

  local lo, hi
  while i <= n and #result > 0 do
    local currinterval = table.remove(result)
    local nextinterval = list[i]
    lo, hi = diff(currinterval, nextinterval)
    if lo then table.insert(result, lo) end
    if hi then table.insert(result, hi) end
    i = i + 1
  end
  return result
end

-- Find the segments of the interval that ARE covered by the interval list.
local function intervallist_intersect(list, interval)
  local i = 1
  local n = #list
  while i <= n and list[i][LO] < interval[LO] do
    i = i + 1
  end

  local intersecting = {}
  local currinterval = { interval[LO], interval[HI], BEG }
  while i <= n and currinterval do
    local nextinterval = list[i]
    if currinterval[HI] > low(nextinterval)
       and currinterval[LO] < high(nextinterval)
    then
      -- We have an intersection.
      local lo = math.max(currinterval[LO], low(nextinterval))
      local hi = math.min(currinterval[HI], high(nextinterval))
      table.insert(intersecting, { lo, hi })
      if currinterval[HI] > high(nextinterval) then
        currinterval = { high(nextinterval), currinterval[HI], BEG }
      else
        currinterval = nil
      end
    end
    i = i + 1
  end

  return intersecting
end

-- Forget an ID and return REMOVE updates for coverage no other ID needs.
function M:remove(id)
  local interval = self.idmap[id]
  self.idmap[id] = nil
  local result
  if interval then
    -- Remove the interval.
    intervallist_remove_by_id(self.ilist, interval[ID])

    -- Figure out the ranges to remove.
    result = intervallist_rdiff(self.ilist, interval)
    for _, v in ipairs(result) do
      v[TYPE] = M.REMOVE
    end
  else
    result = {}
  end
  return result
end

-- Update a tracked segment.
-- Add range to the range tracker.
-- id - Interval ID.
-- lo - Inclusive start point.
-- hi - Exclusive end point.
-- Returns intervals to remove, followed by intervals to add.
-- Return { { lo, hi, type } ... }
function M:update(id, lo, hi)
  if not id or lo >= hi then return {} end

  local results = {}

  -- Get previous interval, if any, and make new interval.
  local oldinterval = self.idmap[id]

  -- If nothing has changed, short circuit the operation.
  if oldinterval and oldinterval[LO] == lo and oldinterval[HI] == hi then
    return results
  end

  -- Need a unique id because the old and new intervals will be in the
  -- list at the same time.
  local uniqueid = {}
  local newintervalbeg = { lo, hi, BEG, uniqueid }
  local newintervalend = { hi, lo, END, uniqueid }
  self.idmap[id] = newintervalbeg

  local toadd = intervallist_rdiff(self.ilist, newintervalbeg)
  for _, v in ipairs(toadd) do
    v[TYPE] = M.ADD
  end
  intervallist_add(self.ilist, newintervalbeg)
  intervallist_add(self.ilist, newintervalend)

  if oldinterval then
    intervallist_remove_by_id(self.ilist, oldinterval[ID])
    results = intervallist_rdiff(self.ilist, oldinterval)
    for _, v in ipairs(results) do
      v[TYPE] = M.REMOVE
    end
  end

  for _, v in ipairs(toadd) do
    table.insert(results, v)
  end

  return results
end

-- Account for insertion of [lo, hi) in the underlying coordinate space.
-- Shift ranges after the insertion, keep overlapping view sizes fixed, and
-- return REMOVE/ADD updates for coverage displaced or exposed by the edit.
function M:insert_segment(lo, hi)
  if lo >= hi then return {} end

  local i = 1
  local n = #self.ilist
  -- Skip items we don't effect.
  while i <= n and lo >= high(self.ilist[i]) do
    i = i + 1
  end

  local result = {}
  local nr = hi - lo
  -- We are less than or inside all remaining intervals in the list.
  while i <= n do
    local interval = self.ilist[i]

    -- Detect when to update.
    if lo < high(interval) then
      if hi <= low(interval) then
        -- Shift the interval, no update.
        local ilo = LO + interval[OFFSET]
        interval[ilo] = interval[ilo] + nr
        local ihi = HI - interval[OFFSET]
        interval[ihi] = interval[ihi] + nr
      elseif interval[OFFSET] == BEG then
        -- We're in the interval. Only create one update.
        local extend = { interval[HI], interval[HI] + nr, BEG }
        local intervals = intervallist_rdiff(self.ilist, extend)
        for _, v in ipairs(intervals) do
          v[TYPE] = M.REMOVE
          table.insert(result, v)
        end
      end
    end
    i = i + 1
  end

  local updates = intervallist_intersect(self.ilist, { lo, hi, BEG })
  for _, v in ipairs(updates) do
    v[TYPE] = M.ADD
    table.insert(result, v)
  end

  return result
end

-- Account for deletion of [lo, hi) in the underlying coordinate space.
-- Shift later ranges back, clamp high bounds to the new exclusive limit max,
-- and return ADD updates for coverage exposed by the edit.
function M:remove_segment(lo, hi, max)
  if lo >= hi then return {} end

  local result = {}
  local nr = hi - lo

  local i = 1
  local n = #self.ilist
  -- Skip items we don't effect.
  while i <= n and lo >= high(self.ilist[i]) do
    i = i + 1
  end

  -- We are likely less than or inside all remaining intervals in the list.
  while i <= n do
    local interval = self.ilist[i]

    -- Detect when to update.
    if lo < high(interval) then
      if hi <= low(interval) then
        -- Removed segment starts and ends below interval.
        -- Shift the interval, no update.
        local ilo = LO + interval[OFFSET]
        interval[ilo] = interval[ilo] - nr
        local ihi = HI - interval[OFFSET]
        interval[ihi] = math.min(interval[ihi] - nr, max)
      else
        -- Segment overlaps current interval.
        if interval[OFFSET] == BEG and (interval[HI] - nr) < max then
          -- We're in the interval. Only create one update.
          local idiff = { interval[HI], math.min(interval[HI] + nr, max + nr), BEG }
          local intervals = intervallist_rdiff(self.ilist, idiff)
          for _, v in ipairs(intervals) do
            v[LO] = v[LO] - nr
            v[HI] = v[HI] - nr
            v[TYPE] = M.ADD
            table.insert(result, v)
          end
        end
        local ihi = HI - interval[OFFSET]
        interval[ihi] = math.min(interval[ihi], max)
      end
    end
    i = i + 1
  end

  return result
end

-- Return REMOVE/ADD pairs to refresh tracked coverage within [lo, hi).
-- Does not change the stored ranges.
function M:update_segment(lo, hi)
  if lo >= hi then return {} end
  local result = {}

  local intervals = intervallist_intersect(self.ilist, { lo, hi, BEG })

  for _, v in ipairs(intervals) do
    v[TYPE] = M.REMOVE
    table.insert(result, v)
    table.insert(result, { v[LO], v[HI], M.ADD })
  end

  return result
end

-- Return whether any tracked range contains p (exclusive of its high bound).
function M:hit(p)
  for _, interval in pairs(self.idmap) do
    if interval[LO] <= p and p < interval[HI] then return true end
  end
  return false
end

-- Return the stored interval, or nil. LO and HI are read-only to callers.
function M:get(id)
  return self.idmap[id]
end

return M
