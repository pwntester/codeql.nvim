local M = {}

M.file_content_query = [[
query {
  repository(owner: "%s", name: "%s") {
    object(expression: "%s:%s") {
      ... on Blob {
        text
      }
    }
  }
}
]]

local function escape_char(string)
  local escaped, _ = string.gsub(string, '["\\]', {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
  })
  return escaped
end

return function(query, ...)
  local opts = { escape = true }
  for _, v in ipairs { ... } do
    if type(v) == "table" then
      opts = vim.tbl_deep_extend("force", opts, v)
      break
    end
  end
  local escaped = {}
  for _, v in ipairs { ... } do
    if type(v) == "string" and opts.escape then
      local encoded = escape_char(v)
      table.insert(escaped, encoded)
    else
      table.insert(escaped, v)
    end
  end
  return string.format(M[query], unpack(escaped))
end
