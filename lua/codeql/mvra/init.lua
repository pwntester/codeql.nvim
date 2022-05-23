local gh = require("codeql.gh")
local util = require("codeql.util")
local mrva_panel = require("codeql.mvra.panel")

local folder = "mvra_results"

local M = {}

---@class MRVAScan
---@field controller string
---@field id string
---@field results table
---@field artifacts table
local MRVAScan = {}
MRVAScan.__index = MRVAScan

---MRVAScan constructor.
---@return MRVAScan
function MRVAScan:new(opts)
  local this = {
    controller = opts.controller,
    id = opts.id,
    results = nil,
    artifacts = nil,
  }
  setmetatable(this, self)
  return this
end

M.MRVAScan = MRVAScan


function MRVAScan:check_workflow_status(cb)
  local url = string.format("/repos/%s/actions/runs/%s", self.controller, self.id)
  gh.run {
    args = { "api", url },
    cb = function(output, stderr)
      if not util.is_blank(stderr) then
        vim.notify(stderr, 2)
      elseif not util.is_blank(output) then
        local results = vim.fn.json_decode(output)
        cb(results.status)
      end
    end
  }
end

function MRVAScan:download_results_index()
  local url = string.format("/repos/%s/actions/runs/%s/artifacts", self.controller, self.id)
  gh.run {
    args = { "api", "--paginate", url, "--jq", "." },
    cb = function(output, stderr)
      if not util.is_blank(stderr) then
        vim.notify(stderr, 2)
      elseif not util.is_blank(output) then
        self.artifacts = util.get_flatten_artifacts_pages(output)
        for _, artifact in ipairs(self.artifacts) do
          if artifact.name == "result-index" then
            local download_url = artifact.archive_download_url
            local path = vim.fn.tempname()
            gh.download {
              url = download_url,
              path = path,
              cb = function()
                -- `-p` sends data to stdout
                local index = vim.fn.system("unzip -p " .. path)
                self.results = vim.fn.json_decode(index)
                self:show_panel()
                self:download_all_results()
              end
            }
          end
        end
      end
    end
  }
end

function MRVAScan:get_projects_with_results()
  local projects_with_results = {}
  -- successes and failures where added later on so we need to check for both version
  local results
  if not util.is_blank(self.results.successes) then
    -- new version
    results = self.results.successes
  else
    -- old version
    results = self.results
  end
  for _, result in ipairs(results) do
    if result.results_count > 0 then
      projects_with_results[result.nwo] = result
    end
  end
  return projects_with_results
end

function MRVAScan:show_panel()
  local projects_with_results = self:get_projects_with_results()
  if #vim.tbl_keys(projects_with_results) > 0 then
    mrva_panel.draw(folder, projects_with_results)
  else
    vim.notify("No results found", 2)
  end
end

function MRVAScan:download_all_results()
  for _, v in pairs(self:get_projects_with_results()) do
    self:download_project_results(v.id, v.nwo)
  end
end

function MRVAScan:download_project_results(projectId, nwo)
  local download_url
  for _, artifact in ipairs(self.artifacts) do
    if projectId == artifact.name then
      download_url = artifact.archive_download_url
      break
    end
  end
  local dir = vim.fn.getcwd() .. "/" .. folder
  if vim.fn.isdirectory(dir) == 0 then
    print("Creating directory " .. dir)
    vim.fn.mkdir(dir)
  end
  local zip_path = string.format(vim.fn.tempname(), ".zip")
  local sarif_path = dir .. "/" .. nwo:gsub("/", "_") .. ".sarif"
  if vim.fn.filereadable(sarif_path) > 0 then
    print("File already downloaded: " .. sarif_path)
    return
  end
  gh.download {
    url = download_url,
    path = zip_path,
    cb = function()
      vim.fn.system(string.format("unzip -p %s results.sarif > %s", zip_path, sarif_path))

      --[[
        inflating: nwo.txt
        inflating: resultcount.txt
        inflating: results.bqrs
        inflating: results.csv
        inflating: results.md


        inflating: nwo.txt
        inflating: resultcount.txt
        inflating: results.bqrs
        inflating: results.sarif
        inflating: sha.txt

      ]]
      --
    end
  }
end

function M.load_scan(run_url)
  run_url = run_url:gsub(".*.com/", "")
  run_url = run_url:gsub("/actions/runs/", "::")
  local opts = {
    controller = vim.split(run_url, "::")[1],
    id = vim.split(run_url, "::")[2],
  }
  local scan = MRVAScan:new(opts)
  scan:check_workflow_status(function(status)
    if status == "completed" then
      scan:download_results_index()
    else
      vim.notify("Scan is not completed yet: " .. status, 2)
    end
  end)
end

return M
