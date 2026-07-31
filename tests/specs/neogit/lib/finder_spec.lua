local async = require("neogit.lib.async")
local config = require("neogit.config")
local Finder = require("neogit.lib.finder")

local original_config_values
local original_fzf_lua

local function wait_for(predicate)
  return vim.wait(500, predicate, 5)
end

local function flush_scheduled()
  local flushed = false
  vim.schedule(function()
    flushed = true
  end)
  assert.is_true(wait_for(function()
    return flushed
  end))
end

local function setup_fzf_lua(scenario)
  config.values = config.get_default_values()
  config.values.integrations = {
    telescope = false,
    diffview = false,
    codediff = false,
    fzf_lua = true,
    mini_pick = false,
    snacks = false,
  }

  package.loaded["fzf-lua"] = {
    fzf_exec = function(entries, opts)
      return scenario(entries, opts)
    end,
  }

  return Finder.create({
    refocus_status = false,
  }):add_entries { "first", "second" }
end

describe("lib.finder fzf-lua integration", function()
  before_each(function()
    original_config_values = config.values
    original_fzf_lua = package.loaded["fzf-lua"]
  end)

  after_each(function()
    config.values = original_config_values
    package.loaded["fzf-lua"] = original_fzf_lua
  end)

  it("completes find_async with nil when fzf-lua closes without an action", function()
    local finder = setup_fzf_lua(function(_, opts)
      local fzf_coroutine = coroutine.create(function()
        opts.winopts.on_close()
      end)
      coroutine.resume(fzf_coroutine)
      return fzf_coroutine
    end)
    local completed = false
    local selection = "pending"

    async.run(function()
      selection = finder:find_async()
      completed = true
    end)

    assert.is_true(wait_for(function()
      return completed
    end))
    assert.is_nil(selection)
  end)

  it("prefers a selection made immediately after fzf-lua closes", function()
    local finder = setup_fzf_lua(function(_, opts)
      opts.winopts.on_close()
      opts.actions.default { "second" }
    end)
    local selections = {}

    finder:find(function(selection)
      table.insert(selections, selection)
    end)

    flush_scheduled()
    assert.are.same({ "second" }, selections)
  end)

  it("completes once when fzf-lua close and abort actions overlap", function()
    local finder = setup_fzf_lua(function(_, opts)
      opts.winopts.on_close()
      opts.actions.esc()
    end)
    local completion_count = 0
    local selection = "pending"

    finder:find(function(value)
      completion_count = completion_count + 1
      selection = value
    end)

    flush_scheduled()
    assert.are.equal(1, completion_count)
    assert.is_nil(selection)
  end)

  it("keeps waiting after fzf-lua hides and accepts a later selection", function()
    local fzf_coroutine
    local finder = setup_fzf_lua(function(_, opts)
      fzf_coroutine = coroutine.create(function()
        coroutine.yield()
        opts.winopts.on_close()
        opts.actions.default { "second" }
      end)
      coroutine.resume(fzf_coroutine)
      opts.winopts.on_close()
      return fzf_coroutine
    end)
    local completion_count = 0
    local selection

    finder:find(function(value)
      completion_count = completion_count + 1
      selection = value
    end)

    flush_scheduled()
    assert.are.equal(0, completion_count)

    coroutine.resume(fzf_coroutine)
    flush_scheduled()
    assert.are.equal(1, completion_count)
    assert.are.equal("second", selection)
  end)
end)
