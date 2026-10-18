local git_harness = require("tests.util.git_harness")
local util = require("tests.util.util")
local neogit = require("neogit")

-- plenary's busted runner only collects `it` blocks inside `describe`.
describe("status view opened from a symlinked directory", function()
  it("closes when Neogit is asked to close it", function()
    local working_dir = git_harness.prepare_repository()
    local link = util.create_temp_dir("status-link") .. "/repo"
    util.system { "ln", "-s", working_dir, link }
    vim.api.nvim_set_current_dir(util.project_dir)
    neogit.setup {}

    neogit.open { cwd = link, kind = "replace" }
    assert.are.same("NeogitStatus", vim.bo.filetype)

    neogit.close()
    assert.are_not.same("NeogitStatus", vim.bo.filetype)
  end)
end)
