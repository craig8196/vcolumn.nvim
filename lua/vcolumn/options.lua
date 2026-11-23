-- Options class for copying, merging, managing options/configurations.
-- Useful for simple data. More complex configurations should use something
-- different.

-- Each object has a default_key for storing default settings and an options_key
-- for storing the actual computed values.
-- The base objects are kept empty to intercept with __index and __newindex
-- calls.

-- Define unique keys.
local default_key = {}
local user_key = {}
local options_key = {}
local key_set = {
  [default_key] = true,
  [user_key] = true,
  [options_key] = true,
}
local key_map = {
  default = default_key,
  user = user_key,
  options = options_key,
}

local Options = {}
local OptionsMetatable = {}

-- Check Options for a function, or forward to the proxy.
function OptionsMetatable.__index(t, k)
  local classfn = rawget(Options, k)
  if classfn ~= nil then
    return classfn
  else
    local options = rawget(t, options_key)
    local options_value = rawget(options, k)
    if type(k) == 'number' or options_value ~= nil then
      return options_value
    else
      local default = rawget(t, default_key)
      return rawget(default, k)
    end
  end
end

-- Update the proxy.
function OptionsMetatable.__newindex(t, k, user_value)
  local options = rawget(t, options_key)
  local user = rawget(t, user_key)
  local default = rawget(t, default_key)

  local default_value = rawget(default, k)
  if type(k) == 'number' then
    rawset(user, k, user_value)
    if type(default_value) == 'function' then
      local prev_user_value = rawget(options, k)
      rawset(options, k, default_value(user_value, prev_user_value))
    else
      rawset(options, k, user_value)
    end
  elseif default_value ~= nil then
    rawset(user, k, user_value)

    local value
    if type(user_value) ~= type(default_value) then
      if type(default_value) == 'function' then
        local prev_user_value = rawget(options, k)
        value = default_value(user_value, prev_user_value)
      elseif type(default_value) == 'table' then
        value = Options.new(default_value, {})
      else
        value = default_value
      end
    elseif type(default_value) == 'table' then
      value = Options.new(default_value, user_value)
    elseif type(user_value) == 'function' and default_value == user_value then
      local prev_user_value = rawget(options, k)
      value = default_value(nil, prev_user_value)
    else
      value = user_value
    end

    rawset(options, k, value)
  end
end

function OptionsMetatable.__pairs(t)
  return next, t[options_key], nil
end

function Options.new(default, user)
  if user == nil then user = {} end
  if type(user) ~= 'table' then user = { user } end

  local newval = {}
  setmetatable(newval, OptionsMetatable)
  rawset(newval, default_key, default)
  rawset(newval, user_key, user)
  rawset(newval, options_key, {})

  for k, v in pairs(user) do
    newval[k] = v
  end

  -- Check that all default keys get populated.
  for k, v in pairs(default) do
    if (type(k) ~= 'number' and user[k] == nil) then
      newval[k] = v
    end
  end

  return newval
end

function Options:get_options()
  return self[options_key]
end

-- Get the user of a proxy value.
function Options:get_user()
  return self[user_key]
end

-- Get all of the private keys as a set.
function Options.get_key_set()
  return key_set
end

-- Get all of the private keys as a name:value map.
function Options.get_key_map()
  return key_map
end

-- Get the named key from the map.
function Options.get_named_key(name)
  return key_map[name]
end

return Options
