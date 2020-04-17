local vim = vim

local M = {}

function M.starts_with(str, start)
   return str:sub(1, #start) == start
end

function M.runcmd(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

function M.table_length(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function M.dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

function M.print_dump(o)
    print(dump(o))
end

function M.json_encode(data)
  local status, result = pcall(vim.fn.json_encode, data)
  if status then
    return result
  else
    return nil, result
  end
end

function M.json_decode(data)
  local status, result = pcall(vim.fn.json_decode, data)
  if status then
    return result
  else
    return nil, result
  end
end

function M.isFile(name)
    if type(name)~="string" then return false end
    local f = io.open(name)
    if f then
        f:close()
        return true
    end
    return false
end

function M.isDir(path)
    if type(path)~="string" then return false end
    local f = io.open(path, "r")
    if f then
        local ok, err, code = f:read(1)
        f:close()
        return code == 21
    end
    return false
end

function M.readJsonFile(path)
    local f = io.open(path, "r")
    local body = f:read("*all")
    f:close()
    local decoded, err = M.json_decode(body)
    if not decoded then
        print("Error!! "..err)
        return nil
    end
    return decoded
end

return M 
