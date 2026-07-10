-- lvim-color-picker: three color tools in one plugin — an interactive slider PICKER, a CONVERTER
-- that cycles a literal between hex / rgb() / hsl(), and an inline HIGHLIGHTER that paints color
-- literals in the buffer — plus a `p` action inside the picker that inserts straight from the live
-- lvim-utils palette. This is the public entry point: setup() merges user opts into the live config,
-- self-themes the panel accents from the palette, starts the highlighter's auto-enable, and installs
-- the :LvimColorPicker command (subcommands: pick / convert / highlight) and the <Plug> maps. The
-- converter's dot-repeat rides the native operatorfunc seam (see convert.lua).
--
---@module "lvim-color-picker"

local config = require("lvim-color-picker.config")

local ok_utils, uu = pcall(require, "lvim-utils.utils")

local M = {}

---@type boolean  one-time registration done
local registered = false

--- Array-replacing deep merge (mirrors lvim-utils.utils.merge) for a standalone install.
---@param target table
---@param opts? table
---@return table target
local function merge(target, opts)
    for k, v in pairs(opts or {}) do
        if type(v) == "table" and type(target[k]) == "table" and not vim.islist(v) then
            merge(target[k], v)
        else
            target[k] = v
        end
    end
    return target
end

--- Self-theme the panel accents from the lvim-utils palette (re-derived on ColorScheme / palette
--- sync); plain links keep the panel legible without lvim-utils.
---@return nil
local function set_highlights()
    local ok_hl, hl = pcall(require, "lvim-utils.highlight")
    if ok_hl and type(hl.bind) == "function" then
        hl.bind(require("lvim-color-picker.highlights").build)
    else
        for _, g in ipairs({ "LvimColorPickerLabel", "LvimColorPickerValue" }) do
            vim.api.nvim_set_hl(0, g, { link = "Normal", default = true })
        end
    end
end

--- Open the slider picker (bare `:LvimColorPicker` / `pick`).
---@return nil
function M.pick()
    require("lvim-color-picker.picker").open()
end

--- Convert the color literal under the cursor to the next syntax in the cycle.
---@return nil
function M.convert()
    require("lvim-color-picker.convert").convert()
end

--- Toggle / set the inline highlighter for the current buffer.
---@param action? "on"|"off"|"toggle"
---@return nil
function M.highlight(action)
    local h = require("lvim-color-picker.highlighter")
    local buf = vim.api.nvim_get_current_buf()
    if action == "on" then
        h.enable(buf)
    elseif action == "off" then
        h.disable(buf)
    else
        h.toggle(buf)
    end
end

--- The :LvimColorPicker dispatcher.
---@param opts table  the nvim_create_user_command argument table
---@return nil
local function command(opts)
    local args = opts.fargs
    local sub = args[1]
    if not sub or sub == "pick" then
        M.pick()
    elseif sub == "convert" then
        M.convert()
    elseif sub == "highlight" then
        M.highlight(args[2] or "toggle")
    else
        vim.notify("lvim-color-picker: unknown subcommand '" .. sub .. "'", vim.log.levels.ERROR)
    end
end

--- Install the user command and the <Plug> maps (always available, independent of default keys).
---@return nil
local function set_commands()
    vim.api.nvim_create_user_command("LvimColorPicker", command, {
        nargs = "*",
        desc = "Color picker / converter / highlighter",
        complete = function(arg)
            return vim.tbl_filter(function(s)
                return s:find(arg, 1, true) == 1
            end, { "pick", "convert", "highlight" })
        end,
    })
    vim.keymap.set({ "n", "i" }, "<Plug>(lvim-color-picker-pick)", function()
        M.pick()
    end, { silent = true, desc = "Open the color picker" })
    vim.keymap.set("n", "<Plug>(lvim-color-picker-convert)", function()
        return require("lvim-color-picker.convert").trigger()
    end, { expr = true, silent = true, desc = "Convert the color under the cursor" })
end

--- Configure and start (idempotent — a second call re-merges config, but the command, maps,
--- highlighter autocmds and highlight bind are installed once).
---@param opts? LvimColorPickerConfig
---@return nil
function M.setup(opts)
    opts = opts or {}
    if ok_utils then
        uu.merge(config, opts)
    else
        merge(config, opts)
    end
    if registered then
        return
    end
    registered = true
    set_highlights()
    set_commands()
    require("lvim-color-picker.highlighter").setup()
end

return M
