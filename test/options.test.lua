
local Options = require('lua.vcolumn.options')
local dumps = require('test.dump').dump
---@diagnostic disable-next-line: unused-function,unused-local
local function dump(o)
  print(dumps(o))
end

local test = {}
local newtest = {}

local function size(t)
  local count = 0
  for _, _ in pairs(t) do count = count + 1 end
  return count
end


local function Set(arr)
  local set = {}
  for _, val in ipairs(arr) do set[val] = true end
  return set
end

-- Simple types.
local simple = Set({ 'nil', 'number', 'string', 'boolean', 'function', 'thread', 'userdata' })
local optkeys = Options.get_key_set()

local function isnotinternal(k)
  local isinternal = optkeys[k]
  return not isinternal
end

local function lentable(t)
  local count = 0
  for k, _ in pairs(t) do
    if isnotinternal(k) then
      count = count + 1
    end
  end
  return count
end

local function eq(a, b)
  local function eqmap(ma, mb)
    for k, v in pairs(ma) do
      if isnotinternal(k) then
        if not eq(v, mb[k]) then
          return false
        end
      end
    end
    for k, v in pairs(mb) do
      if isnotinternal(k) then
        if not eq(v, ma[k]) then return false end
      end
    end
    return true
  end

  if type(a) ~= type(b) then return false end
  if simple[type(a)] then return a == b end
  if lentable(a) ~= lentable(b) then
    return false
  else
    return eqmap(a, b)
  end
end

local function test_config(default, user, expected, testname)
  local c = Options.new(default, user)
  if type(expected) == 'function' then
    expected = expected(c)
  end
  assert(
    eq(expected, c:get_options()),
    'Failed: '..testname..'; expected ~= value: '
      ..dumps(expected)..' ~= '..dumps(c:get_options())
  )
end

local function commastonum(s)
  if type(s) == 'string' then
    local values = {}
    for v in string.gmatch(s, '([^,]+)') do
      table.insert(values, tonumber(v))
    end
    return values
  else
    return {}
  end
end

function test.basic_promoting()
  test_config({ 4 }, { 8 }, { 8 }, 'array number')
  test_config({ 4 }, 'str', { 'str' }, 'array number to string promoted')
  test_config({ 4 }, 8, { 8 }, 'array number promoted')
  test_config({ 'str' }, 'str3', { 'str3' }, 'array string promoted')
  test_config({ 'str' }, 8, { 8 }, 'string to number promoted')
  test_config({ 'str' }, 'str2', { 'str2' }, 'string promoted')
end

function test.table_basics()
  test_config({}, {}, {}, 'table empty valid')
  test_config({}, { 8 }, { 8 }, 'table empty to array valid')
  test_config({}, 8, { 8 }, 'table empty to array promoted')
  test_config({}, { a = 42 }, {}, 'table empty valid, remove extra items')
end

function test.table_advanced()
  test_config({ val = 'str' }, {}, { val = 'str' }, 'table missing value populated')
  test_config({ val = 'str' }, { val = 'other str' }, { val = 'other str' }, 'table valid value difference')
  test_config({ val = 42 }, { val = 'str' }, { val = 42 }, 'table replace with valid type')
  test_config({ val = 42 }, { other = 42 }, { val = 42 }, 'table nonempty remove erroneous entry')
end

function test.array_basics()
  test_config({ 'array', 2 }, {}, {}, 'array nonempty to empty')
  test_config({ 'array', 2 }, { 'string', 3 }, { 'string', 3 }, 'array difference')
  test_config({ 'array', 2 }, { 2 }, { 2 }, 'array length less')
  test_config({ 'array', 2 }, { 2, 3, 4 }, { 2, 3, 4 }, 'array length more')
end

function test.computing_values()
  test_config({ cols = commastonum }, { cols = '3,42' }, { cols = { 3, 42 } }, 'table computed')
  test_config({ commastonum }, { '3,42' }, { { 3, 42 } }, 'array computed')
end

function test.nested_object_access()
  local d1 = { nested = { cols = commastonum } }
  local u1 = { nested = { cols = '3,42' } }
  local c1 = Options.new(d1, u1)
  assert(eq(c1.nested.cols, { 3, 42 }), 'failed nested object access')
end

function test.nested_array_access()
  local d2 = { cols = { commastonum } }
  local u2 = { cols = { '3,42' } }
  local c2 = Options.new(d2, u2)
  assert(eq(c2.cols[1], { 3, 42 }), 'failed nested array access')
end

function test.nil_options()
  local d3 = { nested = { cols = commastonum } }
  local u3 = nil
  local c3 = Options.new(d3, u3)
  assert(eq(c3, { nested = { cols = {} } }), 'failed handle nil options')
end

function test.nested_assign()
  local d3 = { nested = { cols = commastonum } }
  local u3 = nil
  local c3 = Options.new(d3, u3)
  c3.nested = { cols = '3,42' }
  assert(eq(c3, { nested = { cols = { 3, 42 }}}), 'failed nested assign')
end

function test.nested_cols_assign()
  local d = { nested = { cols = commastonum } }
  local c = Options.new(d)
  local nested = c.nested
  nested.cols = '3,42'
  assert(eq(c, { nested = { cols = { 3, 42 }}}))
  assert(eq(c.nested, { cols = { 3, 42 }}))
  assert(eq(Options.get_user(c.nested),  { cols = '3,42' }))
  assert(eq(Options.get_user(c), { nested = { cols = '3,42' }}))
end

function test.no_exist()
  local d = { nested = { cols = commastonum } }
  local c = Options.new(d)
  assert(eq(c.noexist, nil), 'invalid exist')
end

local teststorun
if size(newtest) > 0 then
  teststorun = newtest
else
  teststorun = test
end

for testname, testcase in pairs(teststorun) do
  local ok, msg = pcall(testcase)
  if ok then
    print('PASSED: '..testname)
  else
    print('FAILED: '..testname..' with message: '..tostring(msg))
  end
end

