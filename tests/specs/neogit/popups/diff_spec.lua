local eq = assert.are.same
local diff_actions = require("neogit.popups.diff.actions")
local git_harness = require("tests.util.git_harness")
local util = require("tests.util.util")
local git_repository = require("neogit.lib.git.repository")
local FuzzyFinderBuffer = require("neogit.buffers.fuzzy_finder")

describe("diff popup actions", function()
  local original_fuzzy
  local repository

  before_each(function()
    local working_dir = git_harness.prepare_repository()
    util.system { "git", "branch", "range-other" }
    util.system { "git", "tag", "range-v1" }

    repository = git_repository.instance(working_dir)
    local done, cancelled = repository:dispatch_refresh():wait(5000)
    assert.is_true(done, "repository refresh timed out")
    assert.is_false(cancelled, "repository refresh was cancelled")

    -- Read branch state from Git after all asynchronous repository refreshes have settled.
    repository:reset()
    original_fuzzy = FuzzyFinderBuffer.new
  end)

  after_each(function()
    FuzzyFinderBuffer.new = original_fuzzy
  end)

  local function index_of(candidates, candidate)
    for index, value in ipairs(candidates) do
      if value == candidate then
        return index
      end
    end
  end

  local function count(candidates, candidate)
    local matches = 0
    for _, value in ipairs(candidates) do
      if value == candidate then
        matches = matches + 1
      end
    end
    return matches
  end

  local function range_options(section, item)
    local options

    -- Capture candidates at the finder UI boundary, then cancel before user input.
    FuzzyFinderBuffer.new = function(candidates)
      options = candidates
      return {
        open_async = function()
          return nil
        end,
      }
    end

    diff_actions.range {
      close = function() end,
      get_env = function(_, name)
        if name == "section" then
          return section
        elseif name == "item" then
          return item
        end
      end,
    }

    return options
  end

  local function assert_real_refs_are_ordered(options, head_is_context)
    local branch_index = index_of(options, "range-other")
    local tag_index = index_of(options, "range-v1")
    local head_index = index_of(options, "HEAD")

    assert.is_number(branch_index)
    assert.is_number(tag_index)
    assert.is_number(head_index)
    assert.is_true(branch_index < tag_index)
    if head_is_context then
      eq(1, head_index)
    else
      assert.is_true(tag_index < head_index)
    end
  end

  it("offers the current branch first from a status section", function()
    local options = range_options({ name = "unstaged" }, { name = "a.txt" })

    eq("master", options[1])
    assert.is_nil(index_of(options, "a.txt"))
    assert_real_refs_are_ordered(options)
  end)

  it("offers the selected commit first and current branch next from a log view", function()
    local selected_commit = vim.trim(util.system { "git", "rev-parse", "HEAD~1" })
    local options = range_options({ name = "log" }, { name = selected_commit })

    eq(selected_commit, options[1])
    eq("master", options[2])
    assert_real_refs_are_ordered(options)
  end)

  it("offers the selected commit first and current branch next from a recent view", function()
    local selected_commit = vim.trim(util.system { "git", "rev-parse", "HEAD~1" })
    local options = range_options({ name = "recent" }, { name = selected_commit })

    eq(selected_commit, options[1])
    eq("master", options[2])
    assert_real_refs_are_ordered(options)
  end)

  it("offers HEAD first and only once when detached", function()
    util.system { "git", "checkout", "--detach", "HEAD" }
    repository:reset()

    local options = range_options({ name = "unstaged" }, { name = "a.txt" })

    eq("HEAD", options[1])
    eq(1, count(options, "HEAD"))
    assert_real_refs_are_ordered(options, true)
  end)
end)
