local vim = vim
local uv = vim.loop

local M = {}

function M.run_cmd(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

function M.dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. M.dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

function M.print_dump(o)
    print(M.dump(o))
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

function M.is_file(filename)
  local stat = uv.fs_stat(filename)
  return stat and stat.type == 'file' or false
end

function M.is_dir(filename)
  local stat = uv.fs_stat(filename)
  return stat and stat.type == 'directory' or false
end

function M.read_json_file(path)
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

function M.tbl_slice(tbl, s, e)
    local pos, new = 1, {}
    for i = s, e do
        new[pos] = tbl[i]
        pos = pos + 1
    end
    return new
end

return M
