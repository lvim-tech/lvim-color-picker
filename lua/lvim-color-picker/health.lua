-- lvim-color-picker: :checkhealth lvim-color-picker.
-- Reports the dependency state (lvim-ui powers the picker panel and the palette select; lvim-utils
-- powers the panel accents + the live palette the `p` action draws from), the configured highlighter
-- style/filetypes, and the converter cycle. Read-only — never mutates config or state.
--
---@module "lvim-color-picker.health"

local config = require("lvim-color-picker.config")

local M = {}

--- Run the health report.
---@return nil
function M.check()
    local health = vim.health
    health.start("lvim-color-picker")

    if vim.fn.has("nvim-0.10") == 1 then
        health.ok("Neovim >= 0.10")
    else
        health.error("Neovim >= 0.10 is required (vim.uv, vim.islist, inline virt_text)")
    end

    if pcall(require, "lvim-ui") then
        health.ok("lvim-ui found (the picker panel + palette select)")
    else
        health.error("lvim-ui not found — :LvimColorPicker pick and the palette action need it")
    end

    local ok_utils = pcall(require, "lvim-utils.colors")
    local ok_hl, hl = pcall(require, "lvim-utils.highlight")
    if ok_utils and ok_hl and type(hl.bind) == "function" then
        health.ok("lvim-utils found (panel accents + live palette for `p`)")
    else
        health.warn("lvim-utils not found — panel accents link to Normal, the `p` palette is empty")
    end

    local hlc = config.highlighter
    health.info(
        ("highlighter: style = %s, named = %s, auto = %s"):format(
            hlc.style,
            tostring(hlc.named),
            table.concat(hlc.auto or {}, ", ")
        )
    )
    health.info(("converter cycle: %s"):format(table.concat(config.convert_cycle or {}, " → ")))
    health.info(
        ("picker: mode = %s, output = %s, alpha = %s"):format(
            config.picker.mode,
            config.picker.output,
            tostring(config.picker.alpha)
        )
    )
end

return M
