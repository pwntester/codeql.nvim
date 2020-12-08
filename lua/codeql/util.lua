local cli = require'codeql.cliserver'
local vim = vim
local api = vim.api
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

function M.cmd_parts(input)
  local cmd, cmd_args
  if vim.tbl_islist(input) then
    cmd = input[1]
    cmd_args = {}
    -- Don't mutate our input.
    for i, v in ipairs(input) do
      assert(type(v) == 'string', "input arguments must be strings")
      if i > 1 then
        table.insert(cmd_args, v)
      end
    end
  else
    error("cmd type must be list.")
  end
  return cmd, cmd_args
end

function M.debounce(fn, debounce_time)
  local timer = vim.loop.new_timer()
  local is_debounce_fn = type(debounce_time) == 'function'

  return function(...)
    timer:stop()

    local time = debounce_time
    local args = {...}

    if is_debounce_fn then
      time = debounce_time()
    end

    timer:start(time, 0, vim.schedule_wrap(function() fn(unpack(args)) end))
  end
end

function M.for_each_buf_window(bufnr, fn)
  for _, window in ipairs(vim.fn.win_findbuf(bufnr)) do
    fn(window)
  end
end

function M.err_message(...)
  api.nvim_err_writeln(table.concat(vim.tbl_flatten{...}))
  api.nvim_command("redraw")
end

function M.message(...)
  api.nvim_out_write(table.concat(vim.tbl_flatten{...}).."\n")
  api.nvim_command("redraw")
end

function M.database_upgrades(dbscheme)
  -- "--additional-packs","/Users/pwntester/codeql-home/ctfs/ctf4"
  local json = cli.runSync({'resolve', 'upgrades', '-v', '--log-to-stderr', '--format=json', '--dbscheme', dbscheme})
  local metadata, err = M.json_decode(json)
  if not metadata then
    print("Error resolving database upgrades: "..err)
    return nil
  else
    return metadata
  end
end

function M.query_info(query)
  local json = cli.runSync({'resolve', 'metadata', '-v', '--log-to-stderr', '--format=json', query})
  local metadata, err = M.json_decode(json)
  if not metadata then
    print("Error resolving query metadata: "..err)
    return nil
  else
    return metadata
  end
end

function M.database_info(database)
  local json = cli.runSync({'resolve', 'database', '-v', '--log-to-stderr', '--format=json', database})
  local metadata, err = M.json_decode(json)
  if not metadata then
    print("Error resolving database metadata: "..err)
    return nil
  else
    return metadata
  end
end

function M.bqrs_info(bqrsPath)
  local json = cli.runSync({'bqrs', 'info', '-v', '--log-to-stderr', '--format=json', bqrsPath})
  local decoded, err = M.json_decode(json)
  if not decoded then
    print("ERROR: Could not get BQRS info: "..err)
    return {}
  end
  return decoded
end

function M.resolve_library_path(queryPath)
  local cmd = {'resolve', 'library-path', '-v', '--log-to-stderr', '--format=json', '--query='..queryPath}
  if vim.g.codeql_search_path and #vim.g.codeql_search_path > 0 then
    for _, searchPath in ipairs(vim.g.codeql_search_path) do
      if searchPath ~= '' then
        table.insert(cmd, string.format('--search-path=%s', searchPath))
      end
    end
  end
  local json = cli.runSync(cmd)
  local decoded, err = M.json_decode(json)
  if not decoded then
    print("ERROR: Could not resolve library path: "..err)
    return {}
  end
  return decoded
end

function M.resolve_ram(jvm)
  local cmd = 'codeql resolve ram --format=json'
  if vim.g.codeql_max_ram and vim.g.codeql_max_ram > -1 then
    cmd = cmd..' -M '..vim.g.codeql_max_ram
  end
  local json = M.run_cmd(cmd, true)
  local ram_opts, err = M.json_decode(json)
  if not ram_opts then
    print("ERROR: Could not resolve RAM options: "..err)
    return {}
  else
    if jvm then
      -- --off-heap-ram is not supported by some commands
      ram_opts = vim.tbl_filter(function(i)
        return vim.startswith(i, '-J')
      end, ram_opts)
    end
    print(vim.inspect(ram_opts))
    return ram_opts
  end
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
    print("ERROR: Could not process JSON. "..err)
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
