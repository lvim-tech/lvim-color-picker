-- lvim-color-picker.palette: bridge the LIVE lvim-utils palette into the picker's `p` action —
-- turn every named color in `lvim-utils.colors` (the top-level hex entries plus the nested `git`
-- group) into `lvim-ui.select` items with a per-entry swatch highlight, so a user can drop a
-- palette color into the buffer in the chosen output syntax. Reads the palette on every call, so it
-- always reflects the current theme.
--
---@module "lvim-color-picker.palette"

local api = vim.api

local lib = require("lvim-color-picker.lib")

local M = {}

-- The lvim-utils palette lives in a private table behind an `__index` metatable, so it cannot be
-- enumerated with `pairs`; these are the meaningful named colors offered by the `p` action (the
-- accents + background/foreground tones), read live via `c[name]`. The `git.*` subgroup is added
-- separately.
local NAMES = {
    "black",
    "white",
    "blue",
    "blue_dark",
    "cyan",
    "cyan_dark",
    "green",
    "green_dark",
    "teal",
    "teal_dark",
    "yellow",
    "yellow_dark",
    "orange",
    "orange_dark",
    "magenta",
    "magenta_dark",
    "red",
    "red_dark",
    "purple",
    "purple_dark",
    "bg_light",
    "bg",
    "bg_dark",
    "fg_light",
    "fg",
    "fg_dark",
    "comment",
}
local GIT = { "add", "change", "delete", "change_delete", "untracked" }

--- Whether `v` is a `#rrggbb`(aa) literal (guards against palette slots holding "NONE" / a function).
---@param v any
---@return boolean
local function is_hex(v)
    return type(v) == "string" and v:match("^#%x%x%x%x%x%x%x?%x?$") ~= nil
end

--- Ensure a swatch highlight group for `hex` exists (bg = the color) and return its name — the
--- select row's icon paints in it.
---@param hex string
---@return string
local function swatch_group(hex)
    local name = "LvimColorPickerPal_" .. hex:sub(2)
    if vim.fn.hlexists(name) == 0 then
        local color = lib.parse_at(hex, 0)
        local fg = color and lib.luminance(color.color) > 0.5 and "#000000" or "#ffffff"
        api.nvim_set_hl(0, name, { bg = hex, fg = fg })
    end
    return name
end

--- Build the palette select items from the live lvim-utils palette: one row per named hex color,
--- `{ label = "name  #hex", icon = swatch, hex, color }`, sorted by name. Empty when lvim-utils is
--- absent.
---@return { label: string, icon: string, hl: string, hex: string, color: LvimColor }[]
function M.items()
    local ok, c = pcall(require, "lvim-utils.colors")
    if not ok then
        return {}
    end
    local rows = {}
    local function add(name, hex)
        if not is_hex(hex) then
            return
        end
        local hit = lib.parse_at(hex, 0)
        if hit then
            rows[#rows + 1] = {
                label = ("%-16s %s"):format(name, hex),
                icon = "󰝤",
                hl = swatch_group(hex),
                hex = hex,
                color = hit.color,
            }
        end
    end
    for _, name in ipairs(NAMES) do
        add(name, c[name])
    end
    local git = c.git
    if type(git) == "table" then
        for _, sub in ipairs(GIT) do
            add("git." .. sub, git[sub])
        end
    end
    return rows
end

return M
