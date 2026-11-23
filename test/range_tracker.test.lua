local Tracker = require('lua.vcolumn.range_tracker')
local helpers = require('test.helpers')
local assert_equal = helpers.assert_equal

local test = {}

function test.instantiate()
  local v = Tracker.new()
  assert(nil ~= v)
end

function test.add_one(vm)
  local result = vm:update(101, 0, 38)
  assert_equal(result, { { 0, 38, Tracker.ADD } })
end

function test.add_two_side_by_side_hi(vm)
  vm:update(102, 50, 55)
  local result = vm:update(103, 55, 56)
  assert_equal(result, { { 55, 56, Tracker.ADD } })
end

function test.add_two_side_by_side_lo(vm)
  vm:update(102, 50, 55)
  local result = vm:update(103, 49, 50)
  assert_equal(result, { { 49, 50, Tracker.ADD } })
end

function test.add_overlap_hi(vm)
  vm:update(102, 50, 60)
  local result = vm:update(103, 55, 65)
  assert_equal(result, { { 60, 65, Tracker.ADD } })
end

function test.add_overlap_lo(vm)
  vm:update(102, 50, 60)
  local result = vm:update(103, 45, 55)
  assert_equal(result, { { 45, 50, Tracker.ADD } })
end

function test.remove_none(vm)
  local result = vm:remove(42)
  assert_equal(result, {})
end

function test.remove_one(vm)
  vm:update(103, 50, 60)
  local result = vm:remove(103)
  assert_equal(result, { { 50, 60, Tracker.REMOVE } })
end

function test.update_same(vm)
  vm:update(103, 50, 60)
  local result = vm:update(103, 50, 60)
  assert_equal(result, {})
end

function test.update_repeated(vm)
  local result = vm:update(1000, 0, 59)
  assert_equal(result, { { 0, 59, Tracker.ADD } })
  result = vm:update(1001, 0, 59)
  assert_equal(result, {})
  result = vm:update(1000, 0, 59)
  assert_equal(result, {})
  result = vm:update(1001, 0, 59)
  assert_equal(result, {})
end

function test.update_no_overlap(vm)
  vm:update(103, 50, 60)
  local result = vm:update(103, 60, 70)
  assert_equal(result, {
    { 50, 60, Tracker.REMOVE },
    { 60, 70, Tracker.ADD },
  })
end

function test.update_some_overlap_hi(vm)
  vm:update(103, 50, 60)
  local result = vm:update(103, 55, 70)
  assert_equal(result, {
    { 50, 55, Tracker.REMOVE },
    { 60, 70, Tracker.ADD },
  })
end

function test.update_some_overlap_lo(vm)
  vm:update(103, 50, 60)
  local result = vm:update(103, 45, 55)
  assert_equal(result, {
    { 55, 60, Tracker.REMOVE },
    { 45, 50, Tracker.ADD },
  })
end

function test.update_middle_overlap(vm)
  vm:update(103, 50, 70)
  vm:update(104, 80, 100)
  local result = vm:update(200, 65, 90)
  assert_equal(result, { { 70, 80, Tracker.ADD } })
end

function test.update_no_new(vm)
  vm:update(103, 50, 70)
  vm:update(104, 80, 100)
  vm:update(200, 65, 90)
  local result = vm:update(1001, 50, 100)
  assert_equal(result, {})
end

function test.complex_add(vm)
  vm:update(1001, 1, 2)
  vm:update(1002, 8, 9)
  vm:update(1003, 12, 13)
  vm:update(1004, 25, 26)
  local result = vm:update(1005, 0, 30)
  assert_equal(result, {
    { 0, 1, Tracker.ADD },
    { 2, 8, Tracker.ADD },
    { 9, 12, Tracker.ADD },
    { 13, 25, Tracker.ADD },
    { 26, 30, Tracker.ADD },
  })
end

function test.complex_remove(vm)
  vm:update(1005, 0, 30)
  vm:update(1001, 1, 2)
  vm:update(1002, 8, 9)
  vm:update(1003, 12, 13)
  vm:update(1004, 25, 26)
  local result = vm:remove(1005)
  assert_equal(result, {
    { 0, 1, Tracker.REMOVE },
    { 2, 8, Tracker.REMOVE },
    { 9, 12, Tracker.REMOVE },
    { 13, 25, Tracker.REMOVE },
    { 26, 30, Tracker.REMOVE },
  })
end

function test.insert_segment_low(vm)
  vm:update(1004, 50, 100)
  local result = vm:insert_segment(49, 50)
  assert_equal(result, {})
  result = vm:update(105, 50, 52)
  assert_equal(result, { { 50, 51, Tracker.ADD } })
  local w1004 = vm:get(1004)
  assert(w1004[Tracker.LO] == 51)
  assert(w1004[Tracker.HI] == 101)
end

function test.insert_segment_mid_low(vm)
  vm:update(1004, 50, 100)
  local result = vm:insert_segment(50, 51)
  assert_equal(result, {
    { 100, 101, Tracker.REMOVE },
    { 50, 51, Tracker.ADD },
  })
  result = vm:update(103, 50, 52)
  assert_equal(result, {})
end

function test.insert_segment_mid_high(vm)
  vm:update(1004, 50, 100)
  local result = vm:insert_segment(99, 100)
  assert_equal(result, {
    { 100, 101, Tracker.REMOVE },
    { 99, 100, Tracker.ADD },
  })
  result = vm:update(103, 99, 100)
  assert_equal(result, {})
end

function test.insert_segment_high(vm)
  vm:update(1004, 50, 100)
  local result = vm:insert_segment(100, 101)
  assert_equal(result, {})
end

function test.insert_segment_overlapping_ranges(vm)
  vm:update(103, 50, 100)
  vm:update(105, 80, 120)
  local result = vm:insert_segment(60, 67)
  assert_equal(result, { { 60, 67, Tracker.ADD } })
  local w105 = vm:get(105)
  assert(w105[Tracker.LO] == 87)
  assert(w105[Tracker.HI] == 127)
end

function test.remove_segment_low(vm)
  vm:update(1004, 50, 100)
  local result = vm:remove_segment(49, 50, 1000)
  assert_equal(result, {})
  result = vm:update(105, 99, 100)
  assert_equal(result, { { 99, 100, Tracker.ADD } })
end

function test.remove_segment_mid_low(vm)
  vm:update(1004, 50, 100)
  local result = vm:remove_segment(50, 51, 1000)
  assert_equal(result, { { 99, 100, Tracker.ADD } })
  result = vm:update(103, 99, 100)
  assert_equal(result, {})
end

function test.remove_segment_mid_high(vm)
  vm:update(1004, 50, 100)
  local result = vm:remove_segment(99, 100, 1000)
  assert_equal(result, { { 99, 100, Tracker.ADD } })
  result = vm:update(103, 99, 100)
  assert_equal(result, {})
end

function test.remove_segment_high(vm)
  vm:update(1004, 50, 100)
  local result = vm:remove_segment(100, 101, 1000)
  assert_equal(result, {})
end

function test.remove_segment_max(vm)
  vm:update(1004, 50, 100)
  local result = vm:remove_segment(70, 79, 98)
  assert_equal(result, { { 91, 98, Tracker.ADD } })
  result = vm:update(105, 97, 100)
  assert_equal(result, { { 98, 100, Tracker.ADD } })
end

function test.remove_segment_overlapping_ranges(vm)
  vm:update(103, 50, 100)
  vm:update(105, 80, 120)
  local result = vm:remove_segment(60, 67, 1000)
  assert_equal(result, {})
end

function test.hit_point(vm)
  vm:update(1001, 2, 3)
  vm:update(1002, 4, 5)
  assert(not vm:hit(1))
  assert(not vm:hit(3))
  assert(not vm:hit(5))
  assert(vm:hit(2))
  assert(vm:hit(4))
end

function test.update_segment_lo(vm)
  vm:update(1004, 50, 100)
  local result = vm:update_segment(49, 50)
  assert_equal(result, {})
end

function test.update_segment_mid_lo(vm)
  vm:update(1004, 50, 100)
  local result = vm:update_segment(50, 51)
  assert_equal(result, {
    { 50, 51, Tracker.REMOVE },
    { 50, 51, Tracker.ADD },
  })
end

function test.update_segment_mid_hi(vm)
  vm:update(1004, 50, 100)
  local result = vm:update_segment(99, 100)
  assert_equal(result, {
    { 99, 100, Tracker.REMOVE },
    { 99, 100, Tracker.ADD },
  })
end

function test.update_segment_hi(vm)
  vm:update(1004, 50, 100)
  local result = vm:update_segment(100, 101)
  assert_equal(result, {})
end

function test.update_segment_overlap(vm)
  vm:update(103, 50, 100)
  vm:update(105, 80, 120)
  local result
  result = vm:update_segment(40, 60)
  assert_equal(result, {
    { 50, 60, Tracker.REMOVE },
    { 50, 60, Tracker.ADD },
  })
  result = vm:update_segment(90, 110)
  assert_equal(result, {
    { 90, 100, Tracker.REMOVE },
    { 90, 100, Tracker.ADD },
    { 100, 110, Tracker.REMOVE },
    { 100, 110, Tracker.ADD },
  })
  result = vm:update_segment(110, 130)
  assert_equal(result, {
    { 110, 120, Tracker.REMOVE },
    { 110, 120, Tracker.ADD },
  })
end

function test.update_segment_gap(vm)
  vm:update(103, 50, 100)
  vm:update(105, 110, 130)
  local result
  result = vm:update_segment(99, 111)
  assert_equal(result, {
    { 99, 100, Tracker.REMOVE },
    { 99, 100, Tracker.ADD },
    { 110, 111, Tracker.REMOVE },
    { 110, 111, Tracker.ADD },
  })
end

function test.insert_segment(vm)
  vm:update(103, 1, 58)
  local result
  result = vm:insert_segment(21, 23)
  assert_equal(result, {
    { 58, 60, Tracker.REMOVE },
    { 21, 23, Tracker.ADD },
  })
end

-- Disjoint subtraction must not expand either range across the gap.
function test.disjoint_ranges(vm)
  vm:update('middle', 50, 60)
  assert_equal(vm:update('left', 0, 10), { { 0, 10, Tracker.ADD } })
  assert_equal(vm:update('right', 80, 90), { { 80, 90, Tracker.ADD } })
  assert_equal(vm:remove('left'), { { 0, 10, Tracker.REMOVE } })
  assert_equal(vm:remove('right'), { { 80, 90, Tracker.REMOVE } })
end

function test.move_across_gap(vm)
  vm:update('view', 50, 60)
  assert_equal(vm:update('view', 0, 10), {
    { 50, 60, Tracker.REMOVE },
    { 0, 10, Tracker.ADD },
  })
  assert_equal(vm:update('view', 80, 90), {
    { 0, 10, Tracker.REMOVE },
    { 80, 90, Tracker.ADD },
  })
end

function test.nested_range_boundaries(vm)
  vm:update('outer', 0, 100)
  vm:update('inner', 10, 20)
  assert(vm:hit(0))
  assert(vm:hit(20)) -- The inner range ends, but the outer still covers it.
  assert(not vm:hit(100))
  assert_equal(vm:remove('inner'), {})
  assert(vm:hit(20))
end

function test.remove_duplicate_coverage(vm)
  vm:update('first', 10, 20)
  vm:update('second', 10, 20)
  assert_equal(vm:remove('first'), {})
  assert(vm:get('first') == nil)
  assert(vm:hit(10))
  assert_equal(vm:remove('second'), { { 10, 20, Tracker.REMOVE } })
  assert_equal(vm:remove('second'), {})
  assert(not vm:hit(10))
end

function test.empty_and_invalid_ranges(vm)
  assert(not vm:hit(0))
  assert(vm:get('missing') == nil)
  assert_equal(vm:update_segment(0, 10), {})
  assert_equal(vm:update(nil, 0, 10), {})
  vm:update('view', 10, 20)
  assert_equal(vm:update('view', 10, 10), {})
  assert_equal(vm:update('view', 20, 10), {})
  assert_equal(vm:insert_segment(15, 15), {})
  assert_equal(vm:remove_segment(20, 15, 100), {})
  assert_equal(vm:update_segment(15, 15), {})
  assert_equal(vm:update_segment(20, 15), {})
  assert(vm:get('view')[Tracker.LO] == 10)
  assert(vm:get('view')[Tracker.HI] == 20)
end

helpers.run(test, Tracker.new)
