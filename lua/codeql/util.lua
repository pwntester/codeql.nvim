local cli = require "codeql.cliserver"
local config = require "codeql.config"
local _, Job = pcall(require, "plenary.job")

local M = {}

function M.list_from_archive(zipfile)
  local job = Job:new {
    enable_recording = true,
    command = "unzip",
    args = { "-Z1", zipfile },
  }
  job:sync()
  local output = table.concat(job:result(), "\n")
  local files = vim.split(output, "\n")
  for i, file in ipairs(files) do
    files[i] = M.replace("/" .. file, config.database.sourceLocationPrefix .. "/", "")
  end
  return files
end

function M.uri_to_fname(uri)
  local colon = string.find(uri, ":")
  if not colon then
    return uri
  end
  local scheme = string.sub(uri, 1, colon)
  local path = string.sub(uri, colon + 1)

  if string.find(string.upper(path), "%%SRCROOT%%") then
    if config.database.sourceLocationPrefix then
      path = string.gsub(path, "%%SRCROOT%%", config.database.sourceLocationPrefix)
    else
      path = string.gsub(path, "%%SRCROOT%%", "")
    end
  end

  local orig_fname
  if string.sub(uri, colon + 1, colon + 2) ~= "//" then
    orig_fname = vim.uri_to_fname(scheme .. "//" .. path)
  else
    orig_fname = vim.uri_to_fname(uri)
  end
  return orig_fname
end

function M.regexEscape(str)
  return str:gsub("[%(%)%.%%%+%-%*%?%[%^%$%]]", "%%%1")
end

function M.replace(str, this, that)
  local escaped_this = M.regexEscape(this)
  local escaped_that = that:gsub("%%", "%%%%") -- only % needs to be escaped for 'that'
  return str:gsub(escaped_this, escaped_that)
end

function M.run_cmd(cmd, raw)
  local f = assert(io.popen(cmd, "r"))
  local s = assert(f:read "*a")
  f:close()
  if raw then
    return s
  end
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  s = string.gsub(s, "[\n\r]+", " ")
  return s
end

function M.cmd_parts(input)
  local cmd, cmd_args
  if vim.tbl_islist(input) then
    cmd = input[1]
    cmd_args = {}
    -- Don't mutate our input.
    for i, v in ipairs(input) do
      assert(type(v) == "string", "input arguments must be strings")
      if i > 1 then
        table.insert(cmd_args, v)
      end
    end
  else
    error "cmd type must be list."
  end
  return cmd, cmd_args
end

function M.debounce(fn, debounce_time)
  local timer = vim.loop.new_timer()
  local is_debounce_fn = type(debounce_time) == "function"

  return function(...)
    timer:stop()

    local time = debounce_time
    local args = { ... }

    if is_debounce_fn then
      time = debounce_time()
    end

    timer:start(
      time,
      0,
      vim.schedule_wrap(function()
        fn(unpack(args))
      end)
    )
  end
end

function M.for_each_buf_window(bufnr, fn)
  for _, window in ipairs(vim.fn.win_findbuf(bufnr)) do
    fn(window)
  end
end

function M.err_message(...)
  vim.api.nvim_err_writeln(table.concat(vim.tbl_flatten { ... }))
  vim.api.nvim_command "redraw"
end

function M.message(...)
  vim.api.nvim_out_write(table.concat(vim.tbl_flatten { ... }) .. "\n")
  vim.api.nvim_command "redraw"
end

function M.database_upgrades(dbscheme)
  local status, json = pcall(
    cli.runSync,
    { "resolve", "upgrades", "-v", "--log-to-stderr", "--format=json", "--dbscheme", dbscheme }
  )
  if status then
    local metadata, err = M.json_decode(json)
    if not metadata then
      print("Error resolving database upgrades: " .. err)
      return nil
    else
      return metadata
    end
  else
    print "Error resolving database upgrades"
    return nil
  end
end

function M.query_info(query)
  local status, json = pcall(cli.runSync, { "resolve", "metadata", "-v", "--log-to-stderr", "--format=json", query })
  if status then
    local metadata, err = M.json_decode(json)
    if not metadata then
      print("Error resolving query metadata: " .. err)
      return {}
    else
      return metadata
    end
  else
    print "Error resolving query metadata"
    return {}
  end
end

function M.database_info(database)
  local json = cli.runSync { "resolve", "database", "-v", "--log-to-stderr", "--format=json", database }
  local metadata, err = M.json_decode(json)
  if not metadata then
    print("Error resolving database metadata: " .. err)
    return nil
  else
    return metadata
  end
end

function M.bqrs_info(bqrsPath)
  local json = cli.runSync { "bqrs", "info", "-v", "--log-to-stderr", "--format=json", bqrsPath }
  local decoded, err = M.json_decode(json)
  if not decoded then
    print("ERROR: Could not get BQRS info: " .. err)
    return {}
  end
  return decoded
end

function M.resolve_library_path(queryPath)
  local cmd = { "resolve", "library-path", "-v", "--log-to-stderr", "--format=json", "--query=" .. queryPath }
  local conf = config.get_config()
  if conf.search_path and #conf.search_path > 0 then
    local additionalPacks = table.concat(conf.search_path, ":")
    table.insert(cmd, string.format("--additional-packs=%s", additionalPacks))
  end
  local json = cli.runSync(cmd)
  local decoded, err = M.json_decode(json)
  if not decoded then
    print("ERROR: Could not resolve library path: " .. err)
    return {}
  end
  return decoded
end

function M.resolve_ram(jvm)
  local cmd = "codeql resolve ram --format=json"
  local conf = config.get_config()
  if conf.max_ram and conf.max_ram > -1 then
    cmd = cmd .. " -M " .. conf.max_ram
  end
  local json = M.run_cmd(cmd, true)
  local ram_opts, err = M.json_decode(json)
  if not ram_opts then
    print("ERROR: Could not resolve RAM options: " .. err)
    return {}
  else
    if jvm then
      -- --off-heap-ram is not supported by some commands
      ram_opts = vim.tbl_filter(function(i)
        return vim.startswith(i, "-J")
      end, ram_opts)
    end
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
  local stat = vim.loop.fs_stat(filename)
  return stat and stat.type == "file" or false
end

function M.is_dir(filename)
  local stat = vim.loop.fs_stat(filename)
  return stat and stat.type == "directory" or false
end

function M.read_json_file(path)
  local f = io.open(path, "r")
  local body = f:read "*all"
  f:close()
  local decoded, err = M.json_decode(body)
  if not decoded then
    M.err_message("Could not process JSON. " .. err)
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

function M.get_user_input_char()
  local c = vim.fn.getchar()
  while type(c) ~= "number" do
    c = vim.fn.getchar()
  end
  return vim.fn.nr2char(c)
end

local special_buffers = {
  filetype = {
    "help",
    "fortifytestpane",
    "fortifyauditpane",
    "qf",
    "goterm",
    "codeql_panel",
    "codeql_explorer",
    "terminal",
    "packer",
    "NvimTree",
    "octo",
    "octo_panel",
    "aerieal",
    "Trouble",
    "dashboard",
    "frecency",
    "TelescopePrompt",
    "TelescopeResults",
    "NeogitStatus",
    "notify",
  },
}

return M
