
local M = {}

local function _dumptoissimple(o)
  local count = 0
  for _, v in pairs(o) do
    count = count + 1
    if type(v) == 'table' or count > 2 then
      return false
    end
  end
  return true
end

local function _dumpto(o, out, level)
 if type(o) == 'table' then
   local issimple = level == 0 or _dumptoissimple(o)
   local newline = issimple and ' ' or '\n'
   local indent = issimple and '' or string.rep(' ', level * 2)
   local closedent = issimple and '' or string.rep(' ', (level - 1) * 2)
   local subdent = level == 0 and 0 or (level + 1)
   table.insert(out, '{' .. newline)
   local has = false
   for k,v in pairs(o) do
     has = true
     table.insert(out, indent .. '[')
     table.insert(out, k)
     table.insert(out, '] = ')
     _dumpto(v, out, subdent)
     table.insert(out, ',' .. newline)
   end
   if has then
     table.remove(out)
     table.insert(out, newline)
   end
   table.insert(out, closedent .. '}')
 elseif type(o) == 'string' then
    table.insert(out, '\'')
    table.insert(out, o)
    table.insert(out, '\'')
 else
   table.insert(out, tostring(o))
 end
 return out
end

function M.dump(o)
  return table.concat(_dumpto(o, {}, 1))
end

function M.dumptoline(o)
  return table.concat(_dumpto(o, {}, 0))
end

return M
