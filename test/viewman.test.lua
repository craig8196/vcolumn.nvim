
local VM = require('lua.vcolumn.viewman')
local dumps = require('test.dump').dump
---@diagnostic disable-next-line: unused-function,unused-local
local function dump(o)
  print(dumps(o))
end


local function resulteq(a, b)
  if not a or not b then
    print('One or more inputs are nil.')
    return false
  end
  if not #a == #b then
    print('Lengths are not equal.')
    return false
  end
  for i, v in ipairs(a) do
    if b[i] ~= v then
      print('Values are incorrect at '..i..' lvalue="'..v..'", rvalue="'..b[i]..'".')
      return false
    end
  end
  return true
end

local function size(t)
  local count = 0
  for _, _ in pairs(t) do count = count + 1 end
  return count
end


local test = {}
local newtest = {}

function test.instantiate()
  local v = VM.new()
  assert(nil ~= v)
end

function test.add_one(vm)
  local result = vm:update(101, 0, 38)
  assert(#result == 1)
  assert(resulteq(result[1], { 0, 38, VM.ADD }))
end

function test.add_two_side_by_side_hi(vm)
  vm:update(102, 50, 55)
  local result = vm:update(103, 55, 56)
  assert(#result == 1)
  assert(resulteq(result[1], { 55, 56, VM.ADD }))
end

function test.add_two_side_by_side_lo(vm)
  vm:update(102, 50, 55)
  local result = vm:update(103, 49, 50)
  assert(#result == 1)
  assert(resulteq(result[1], { 49, 50, VM.ADD }))
end

function test.add_overlap_hi(vm)
  vm:update(102, 50, 60)
  local result = vm:update(103, 55, 65)
  assert(#result == 1)
  assert(resulteq(result[1], { 60, 65, VM.ADD }))
end

function test.add_overlap_lo(vm)
  vm:update(102, 50, 60)
  local result = vm:update(103, 45, 55)
  assert(#result == 1)
  assert(resulteq(result[1], { 45, 50, VM.ADD }))
end

function test.remove_none(vm)
  local result = vm:remove(42)
  assert(#result == 0)
end

function test.remove_one(vm)
  vm:update(103, 50, 60)
  local result = vm:remove(103)
  assert(#result == 1)
  assert(resulteq(result[1], { 50, 60, VM.REMOVE }))
end

function test.update_same(vm)
  vm:update(103, 50, 60)
  local result = vm:update(103, 50, 60)
  assert(#result == 0)
end

function test.update_repeated(vm)
  local result = vm:update(1000, 0, 59)
  assert(#result == 1)
  assert(resulteq(result[1], { 0, 59, VM.ADD }))
  result = vm:update(1001, 0, 59)
  assert(#result == 0)
  result = vm:update(1000, 0, 59)
  assert(#result == 0)
  result = vm:update(1001, 0, 59)
  assert(#result == 0)
end

function test.update_no_overlap(vm)
  vm:update(103, 50, 60)
  local result = vm:update(103, 60, 70)
  assert(#result == 2)
  assert(resulteq(result[1], { 50, 60, VM.REMOVE }))
  assert(resulteq(result[2], { 60, 70, VM.ADD }))
end

function test.update_some_overlap_hi(vm)
  vm:update(103, 50, 60)
  local result = vm:update(103, 55, 70)
  assert(#result == 2)
  assert(resulteq(result[1], { 50, 55, VM.REMOVE }))
  assert(resulteq(result[2], { 60, 70, VM.ADD }))
end

function test.update_some_overlap_lo(vm)
  vm:update(103, 50, 60)
  local result = vm:update(103, 45, 55)
  assert(#result == 2)
  assert(resulteq(result[1], { 55, 60, VM.REMOVE }))
  assert(resulteq(result[2], { 45, 50, VM.ADD }))
end

function test.update_middle_overlap(vm)
  vm:update(103, 50, 70)
  vm:update(104, 80, 100)
  local result = vm:update(200, 65, 90)
  assert(#result == 1)
  assert(resulteq(result[1], { 70, 80, VM.ADD }))
end

function test.update_no_new(vm)
  vm:update(103, 50, 70)
  vm:update(104, 80, 100)
  vm:update(200, 65, 90)
  local result = vm:update(1001, 50, 100)
  assert(#result == 0)
end

function test.complex_add(vm)
  vm:update(1001, 1, 2)
  vm:update(1002, 8, 9)
  vm:update(1003, 12, 13)
  vm:update(1004, 25, 26)
  local result = vm:update(1005, 0, 30)
  assert(#result == 5)
  assert(resulteq(result[1], { 0, 1, VM.ADD }))
  assert(resulteq(result[2], { 2, 8, VM.ADD }))
  assert(resulteq(result[3], { 9, 12, VM.ADD }))
  assert(resulteq(result[4], { 13, 25, VM.ADD }))
  assert(resulteq(result[5], { 26, 30, VM.ADD }))
end

function test.complex_remove(vm)
  vm:update(1005, 0, 30)
  vm:update(1001, 1, 2)
  vm:update(1002, 8, 9)
  vm:update(1003, 12, 13)
  vm:update(1004, 25, 26)
  local result = vm:remove(1005)
  assert(#result == 5)
  assert(resulteq(result[1], { 0, 1, VM.REMOVE }))
  assert(resulteq(result[2], { 2, 8, VM.REMOVE }))
  assert(resulteq(result[3], { 9, 12, VM.REMOVE }))
  assert(resulteq(result[4], { 13, 25, VM.REMOVE }))
  assert(resulteq(result[5], { 26, 30, VM.REMOVE }))
end

function test.insert_segment_low(vm)
  vm:update(1004, 50, 100)
  local result = vm:insert_segment(49, 50)
  assert(#result == 0)
  result = vm:update(105, 50, 52)
  assert(#result == 1)
  assert(resulteq(result[1], { 50, 51, VM.ADD }))
  local w1004 = vm:get(1004)
  assert(w1004[VM.LO] == 51)
  assert(w1004[VM.HI] == 101)
end

function test.insert_segment_mid_low(vm)
  vm:update(1004, 50, 100)
  local result = vm:insert_segment(50, 51)
  assert(#result == 2)
  assert(resulteq(result[1], { 100, 101, VM.REMOVE }))
  assert(resulteq(result[2], { 50, 51, VM.ADD }))
  result = vm:update(103, 50, 52)
  assert(#result == 0)
end

function test.insert_segment_mid_high(vm)
  vm:update(1004, 50, 100)
  local result = vm:insert_segment(99, 100)
  assert(#result == 2)
  assert(resulteq(result[1], { 100, 101, VM.REMOVE }))
  assert(resulteq(result[2], { 99, 100, VM.ADD }))
  result = vm:update(103, 99, 100)
  assert(#result == 0)
end

function test.insert_segment_high(vm)
  vm:update(1004, 50, 100)
  local result = vm:insert_segment(100, 101)
  assert(#result == 0)
end

function test.insert_segment_overlapping_windows(vm)
  vm:update(103, 50, 100)
  vm:update(105, 80, 120)
  local result = vm:insert_segment(60, 67)
  assert(#result == 1)
  assert(resulteq(result[1], { 60, 67, VM.ADD }))
  local w105 = vm:get(105)
  assert(w105[VM.LO] == 87)
  assert(w105[VM.HI] == 127)
end

function test.remove_segment_low(vm)
  vm:update(1004, 50, 100)
  local result = vm:remove_segment(49, 50, 1000)
  assert(#result == 0)
  result = vm:update(105, 99, 100)
  assert(#result == 1)
  assert(resulteq(result[1], { 99, 100, VM.ADD }))
end

function test.remove_segment_mid_low(vm)
  vm:update(1004, 50, 100)
  local result = vm:remove_segment(50, 51, 1000)
  assert(#result == 1)
  assert(resulteq(result[1], { 99, 100, VM.ADD }))
  result = vm:update(103, 99, 100)
  assert(#result == 0)
end

function test.remove_segment_mid_high(vm)
  vm:update(1004, 50, 100)
  local result = vm:remove_segment(99, 100, 1000)
  assert(#result == 1)
  assert(resulteq(result[1], { 99, 100, VM.ADD }))
  result = vm:update(103, 99, 100)
  assert(#result == 0)
end

function test.remove_segment_high(vm)
  vm:update(1004, 50, 100)
  local result = vm:remove_segment(100, 101, 1000)
  assert(#result == 0)
end

function test.remove_segment_max(vm)
  vm:update(1004, 50, 100)
  local result = vm:remove_segment(70, 79, 98)
  assert(#result == 1)
  assert(resulteq(result[1], { 91, 98, VM.ADD }))
  result = vm:update(105, 97, 100)
  assert(#result == 1)
  assert(resulteq(result[1], { 98, 100, VM.ADD }))
end

function test.remove_segment_overlapping_windows(vm)
  vm:update(103, 50, 100)
  vm:update(105, 80, 120)
  local result = vm:remove_segment(60, 67, 1000)
  assert(#result == 0)
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
  assert(#result == 0)
end

function test.update_segment_mid_lo(vm)
  vm:update(1004, 50, 100)
  local result = vm:update_segment(50, 51)
  assert(#result == 2)
  assert(resulteq(result[1], { 50, 51, VM.REMOVE }))
  assert(resulteq(result[2], { 50, 51, VM.ADD }))
end

function test.update_segment_mid_hi(vm)
  vm:update(1004, 50, 100)
  local result = vm:update_segment(99, 100)
  assert(#result == 2)
  assert(resulteq(result[1], { 99, 100, VM.REMOVE }))
  assert(resulteq(result[2], { 99, 100, VM.ADD }))
end

function test.update_segment_hi(vm)
  vm:update(1004, 50, 100)
  local result = vm:insert_segment(100, 101)
  assert(#result == 0)
end

function test.update_segment_overlap(vm)
  vm:update(103, 50, 100)
  vm:update(105, 80, 120)
  local result
  result = vm:update_segment(40, 60)
  assert(#result == 2)
  assert(resulteq(result[1], { 50, 60, VM.REMOVE }))
  assert(resulteq(result[2], { 50, 60, VM.ADD }))
  result = vm:update_segment(90, 110)
  assert(#result == 4)
  assert(resulteq(result[1], { 90, 100, VM.REMOVE }))
  assert(resulteq(result[2], { 90, 100, VM.ADD }))
  assert(resulteq(result[3], { 100, 110, VM.REMOVE }))
  assert(resulteq(result[4], { 100, 110, VM.ADD }))
  result = vm:update_segment(110, 130)
  assert(#result == 2)
  assert(resulteq(result[1], { 110, 120, VM.REMOVE }))
  assert(resulteq(result[2], { 110, 120, VM.ADD }))
end

function test.update_segment_gap(vm)
  vm:update(103, 50, 100)
  vm:update(105, 110, 130)
  local result
  result = vm:update_segment(99, 111)
  assert(#result == 4)
  assert(resulteq(result[1], { 99, 100, VM.REMOVE }))
  assert(resulteq(result[2], { 99, 100, VM.ADD }))
  assert(resulteq(result[3], { 110, 111, VM.REMOVE }))
  assert(resulteq(result[4], { 110, 111, VM.ADD }))
end

function test.insert_segment(vm)
  vm:update(103, 1, 58)
  local result
  result = vm:insert_segment(21, 23)
  assert(#result == 2)
  assert(resulteq(result[1], { 58, 60, VM.REMOVE }))
  assert(resulteq(result[2], { 21, 23, VM.ADD }))
end

local teststorun
if size(newtest) > 0 then
  teststorun = newtest
else
  teststorun = test
end

for testname, testcase in pairs(teststorun) do
  local vm = VM.new()
  local ok, msg = pcall(testcase, vm)
  if ok then
    print('PASSED: '..testname)
  else
    print('FAILED: '..testname..' with message: '..tostring(msg))
  end
end

