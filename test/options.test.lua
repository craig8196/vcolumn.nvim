local Options = require('lua.vcolumn.options')
local dumps = require('test.dump').dump
local helpers = require('test.helpers')

local test = {}
local options_key = Options.get_named_key('options')

-- Compare effective values rather than proxy internals. Lua 5.1/LuaJIT
-- does not use __pairs, unlike newer standalone Lua versions.
local function eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return a == b end
  a = rawget(a, options_key) or a
  b = rawget(b, options_key) or b
  for k, value in pairs(a) do
    if not eq(value, b[k]) then return false end
  end
  for k, value in pairs(b) do
    if not eq(a[k], value) then return false end
  end
  return true
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

function test.false_and_unknown_options()
  local options = Options.new({ enabled = true }, { enabled = false })
  assert(options.enabled == false)
  options.enabled = true
  assert(options.enabled == true)
  options.enabled = false
  assert(options.enabled == false)
  options.unknown = 42
  assert(options.unknown == nil)
  assert(options:get_user().unknown == nil)
end

function test.recompute_on_assignment()
  local function accumulate(value, previous)
    return (previous or 0) + (value or 0)
  end
  local options = Options.new({ total = accumulate }, { total = 3 })
  assert(options.total == 3)
  options.total = 4
  assert(options.total == 7)
  assert(options:get_user().total == 4)
end

helpers.run(test)
