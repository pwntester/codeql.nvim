local cli = require "codeql.cliserver"
local config = require "codeql.config"
local Job = require "plenary.job"

local M = {}

local cache = {
  database_upgrades = {},
  library_paths = {},
  databases = {},
  ram = nil,
  qlpacks = nil,
}

--- Apply mappings to a buffer
function M.apply_mappings()
  local mappings = require "codeql.mappings"
  local conf = config.get_config()
  for action, value in pairs(conf.mappings) do
    if not M.is_blank(value)
        and not M.is_blank(action)
        and not M.is_blank(value.lhs)
        and not M.is_blank(mappings[action])
    then
      if M.is_blank(value.desc) then
        value.desc = ""
      end
      local mapping_opts = { silent = true, noremap = true, desc = value.desc }
      for _, mode in ipairs(value.modes) do
        vim.api.nvim_buf_set_keymap(0, mode, value.lhs, mappings[action], mapping_opts)
      end
    end
  end
end

function M.get_current_position()
  local modeInfo = vim.api.nvim_get_mode()
  local mode = modeInfo.mode

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cline, ccol = cursor[1], cursor[2]
  local vline, vcol = vim.fn.line "v", vim.fn.col "v"

  local sline, scol
  local eline, ecol
  if cline == vline then
    if ccol <= vcol then
      sline, scol = cline, ccol
      eline, ecol = vline, vcol
      scol = scol + 1
    else
      sline, scol = vline, vcol
      eline, ecol = cline, ccol
      ecol = ecol + 1
    end
  elseif cline < vline then
    sline, scol = cline, ccol
    eline, ecol = vline, vcol
    scol = scol + 1
  else
    sline, scol = vline, vcol
    eline, ecol = cline, ccol
    ecol = ecol + 1
  end

  if mode == "V" or mode == "CTRL-V" or mode == "\22" then
    scol = 1
    ecol = nil
  end

  local pos = { sline, scol, eline, ecol }
  return pos
end

function M.get_current_selection()
  local pos = M.get_current_position()
  local sline, scol, eline, ecol = pos[1], pos[2], pos[3], pos[4]
  local lines = vim.api.nvim_buf_get_lines(0, sline - 1, eline, 0)
  if #lines == 0 then
    return
  end

  local startText, endText
  if #lines == 1 then
    startText = string.sub(lines[1], scol, ecol)
  else
    startText = string.sub(lines[1], scol)
    endText = string.sub(lines[#lines], 1, ecol)
  end
  local selection = { startText }
  if #lines > 2 then
    vim.list_extend(selection, vim.list_slice(lines, 2, #lines - 1))
  end
  table.insert(selection, endText)

  return selection
end

function M.get_current_position_orig()
  local srow, scol, erow, ecol

  if vim.fn.getpos("'<")[2] == vim.fn.getcurpos()[2] and vim.fn.getpos("'<")[3] == vim.fn.getcurpos()[3] then
    srow = vim.fn.getpos("'<")[2]
    scol = vim.fn.getpos("'<")[3]
    erow = vim.fn.getpos("'>")[2]
    ecol = vim.fn.getpos("'>")[3]

    ecol = ecol == 2147483647 and 1 + vim.fn.len(vim.fn.getline(erow)) or 1 + ecol
  else
    srow = vim.fn.getcurpos()[2]
    scol = vim.fn.getcurpos()[3]
    erow = vim.fn.getcurpos()[2]
    ecol = vim.fn.getcurpos()[3]
  end

  local pos = { srow, scol, erow, ecol }
  return pos
end

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

function M.err_message(msg, opts)
  opts = opts or { title = "CodeQL" }
  vim.notify(msg, vim.log.levels.ERROR, opts)
end

function M.message(msg, opts)
  opts = opts or { title = "CodeQL" }
  vim.notify(msg, vim.log.levels.INFO, opts)
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

function M.database_upgrades(dbscheme)
  if cache.database_upgrades[dbscheme] then
    return cache.database_upgrades[dbscheme]
  end
  local json = cli.runSync { "resolve", "upgrades", "--format=json", "--dbscheme", dbscheme }
  local metadata, err = M.json_decode(json)
  if not metadata then
    M.err_message("Error resolving database upgrades: " .. err)
    return
  end
  cache.database_upgrades[dbscheme] = metadata
  return metadata
end

function M.database_upgrade(path)
  M.message("Upgrading DB")
  cli.runSync { "database", "upgrade", path }
end

function M.query_info(query)
  local json = cli.runSync { "resolve", "metadata", "--format=json", query }
  local metadata, err = M.json_decode(json)
  if not metadata then
    M.err_message("Error resolving query metadata: " .. err)
    return
  end
  return metadata
end

function M.database_info(database)
  if cache.databases[database] then
    return cache.databases[database]
  end
  local json = cli.runSync { "resolve", "database", "--format=json", database }
  local metadata, err = M.json_decode(json)
  if not metadata then
    M.err_message("Error resolving database metadata: " .. err)
    return
  end
  cache.databases[database] = metadata
  return metadata
end

function M.bqrs_info(bqrsPath, queryPath)
  local json = cli.runSync { "bqrs", "info", "--format=json", bqrsPath }
  if json ~= "" and json ~= vim.NIL and json then
    local decoded, err = M.json_decode(json)
    if not decoded then
      M.err_message(string.format("ERROR: Could not get BQRS info for %s: %s", queryPath, vim.inspect(err)))
      return
    end
    return decoded
  end
  M.err_message(string.format("ERROR: Could not get BQRS info for %s.", queryPath))
end

function M.resolve_library_path(queryPath)
  if cache.library_paths[queryPath] then
    return cache.library_paths[queryPath]
  end
  local cmd = { "resolve", "library-path", "-v", "--log-to-stderr", "--format=json", "--query=" .. queryPath }
  local conf = config.get_config()
  if conf.search_path and #conf.search_path > 0 then
    local additionalPacks = table.concat(conf.search_path, ":")
    table.insert(cmd, string.format("--additional-packs=%s", additionalPacks))
  end
  local json = cli.runSync(cmd)
  local decoded, err = M.json_decode(json)
  if not decoded then
    M.err_message("ERROR: Could not resolve library path: " .. err)
    return
  end
  cache.library_paths[queryPath] = decoded
  return decoded
end

function M.resolve_qlpacks()
  if cache.qlpacks then
    return cache.qlpacks
  end
  local cmd = { "resolve", "qlpacks", "--format=json" }
  local conf = config.get_config()
  if conf.search_path and #conf.search_path > 0 then
    local additionalPacks = table.concat(conf.search_path, ":")
    table.insert(cmd, string.format("--additional-packs=%s", additionalPacks))
  end
  local json = cli.runSync(cmd)
  local decoded, err = M.json_decode(json)
  if not decoded then
    M.err_message("ERROR: Could not resolve qlpacks: " .. err)
    return
  end
  cache.qlpacks = decoded
  return decoded
end

function M.resolve_ram()
  if cache.ram then
    return cache.ram
  end
  local cmd = { "resolve", "ram", "--format=json" }
  local conf = config.get_config()
  if conf.max_ram and conf.max_ram > -1 then
    table.insert(cmd, "-M")
    table.insert(cmd, conf.max_ram)
  end
  local json = cli.runSync(cmd)
  local ram_opts, err = M.json_decode(json)
  if not ram_opts then
    M.err_message("ERROR: Could not resolve RAM options: " .. err)
    return
  end
  ram_opts = vim.tbl_filter(function(i)
    return vim.startswith(i, "-J")
  end, ram_opts)
  cache.ram = ram_opts
  M.message("Memory options " .. vim.inspect(ram_opts))
  return ram_opts
end

function M.is_blank(s)
  return (
      s == nil
          or s == vim.NIL
          or (type(s) == "string" and string.match(s, "%S") == nil)
          or (type(s) == "table" and next(s) == nil)
      )
end

function M.get_flatten_artifacts_pages(text)
  local results = {}
  local page_outputs = vim.split(text, "\n")
  for _, page in ipairs(page_outputs) do
    local decoded_page = vim.fn.json_decode(page)
    vim.list_extend(results, decoded_page.artifacts)
  end
  return results
end

return M
