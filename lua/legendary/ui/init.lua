---@type LegendaryConfig
local Config = require('legendary.config')
---@type LegendaryState
local State = require('legendary.data.state')
local ItemGroup = require('legendary.data.itemgroup')
local Format = require('legendary.ui.format')
local Executor = require('legendary.api.executor')
local Log = require('legendary.log')

local function update_item_frecency_score(item)
  if Config.sort.frecency ~= false then
    local has_sqlite, _ = pcall(require, 'sqlite')
    if has_sqlite then
      Log.trace('Updating scoring data for selected item.')
      local DbClient = require('legendary.api.db.client').init()
      DbClient.update_item_score(item)
    else
      Log.debug('Config.sort.frecency is enabled, but sqlite is not availabe, so frecency is automatically disabled.')
    end
  end
end

---@class LegendaryUi
---@field select fun(opts:LegendaryFindOpts)
local M = {}

---@class LegendaryFindOpts
---@field filters LegendaryItemFilter[]
---@field select_prompt string|fun():string
---@field formatter LegendaryItemFormatter

---@param opts LegendaryFindOpts
---@param itemlist ItemList
---@overload fun(opts:LegendaryFindOpts)
local function select_inner(opts, itemlist)
  if itemlist then
    Log.trace('Relaunching select UI for an item group')
  else
    Log.trace('Launching select UI')
  end

  opts = opts or {}
  local prompt = opts.select_prompt or Config.select_prompt
  if type(prompt) == 'function' then
    prompt = prompt()
  end

  local context = Executor.build_pre_context()

  -- Apply sorting if needed. Note, the internal
  -- implementation of `sort_inplace` checks if
  -- sorting is actually needed and does nothing
  -- if it does not need to be sorted.
  State.items:sort_inplace()

  -- in addition to user filters, we also need to filter by buf
  local items = vim.tbl_filter(function(item)
    local item_buf = vim.tbl_get(item, 'opts', 'buffer')
    return item_buf == nil or item_buf == context.buf
  end, (itemlist or State.items):filter(opts.filters or {}))

  local padding = Format.compute_padding(items, opts.formatter or Config.default_item_formatter, context.mode)

  vim.ui.select(items, {
    prompt = prompt,
    kind = 'legendary.nvim',
    format_item = function(item)
      return Format.format_item(item, opts.formatter or Config.default_item_formatter, padding, context.mode)
    end,
  }, function(selected)
    if not selected then
      return
    end

    local ok, err = pcall(update_item_frecency_score, selected)
    if not ok then
      Log.error('Failed to update frecency score: %s', err)
    end

    State.most_recent_item = selected
    if selected.class == ItemGroup then
      return select_inner(opts, selected.items)
    end

    Log.trace('Preparing to execute selected item')
    Executor.exec_item(selected, context)
  end)
end

---Select an item
---@param opts LegendaryFindOpts
function M.select(opts)
  select_inner(opts)
end

return M
