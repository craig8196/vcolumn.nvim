local M = {}

function M.startswith(s, a) return s:sub(0, 1) == a end

function M.parse_cols(columns, tw)
  local function parse_value(v)
    if M.startswith(v, '+') and tw > 0 then return tw + tonumber(v)
    elseif M.startswith(v, '-') and tw > 0 then return tw + tonumber(v)
    else return tonumber(v) end
  end

  local function parse_input(cols)
    local values = {}
    local n
    if type(cols) == 'string' then
      -- Split on comma and space.
      for v in string.gmatch(cols, '([^ ,]+)') do
        n = parse_value(v)
        if n >= 0 then
          table.insert(values, n)
        end
      end
    elseif type(cols) == 'table' then
      for _, v in ipairs(cols) do
        if type(v) == 'string' then
          n = parse_value(v)
        elseif type(v) == 'number' then
          n = v
        else
          n = -1
        end

        if n >= 0 then
          table.insert(values, n)
        end
      end
    end

    -- To make sure that we align with the buildin colorcolumn behavior we need
    -- to adjust from lua 1-indexing to nvim 0-indexing.
    for i, v in ipairs(values) do
      values[i] = v - 1
    end

    return values
  end

  if type(columns) == 'function' then columns = columns(tw) end
  columns = parse_input(columns)
  table.sort(columns)
  return columns
end

return M
