local M = {}

-- Compare nested result arrays, including their lengths.
function M.assert_equal(actual, expected)
  if type(expected) ~= 'table' then
    assert(actual == expected,
      'expected '..tostring(expected)..', got '..tostring(actual))
    return
  end
  assert(type(actual) == 'table', 'expected a table, got '..type(actual))
  assert(#actual == #expected,
    'expected length '..#expected..', got '..#actual)
  for i, value in ipairs(expected) do
    M.assert_equal(actual[i], value)
  end
end

-- Run in name order, with optional fresh state per case. Fail the command
-- after reporting all failures, so shell scripts can detect a broken suite.
function M.run(tests, new_state)
  local names = {}
  for name in pairs(tests) do names[#names + 1] = name end
  table.sort(names)

  local failed = 0
  for _, name in ipairs(names) do
    local ok, message = xpcall(function()
      tests[name](new_state and new_state())
    end, debug.traceback)
    if not ok then
      failed = failed + 1
      io.stderr:write('FAILED: '..name..': '..tostring(message)..'\n')
    end
  end
  print(('%d passed, %d failed'):format(#names - failed, failed))
  assert(failed == 0, 'test suite failed')
end

return M
