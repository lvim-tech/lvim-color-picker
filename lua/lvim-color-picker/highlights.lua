-- lvim-color-picker.highlights: the PANEL accents (the slider track, the filter chips, the value
-- cell). The per-color swatch groups (LvimColorPickerSwatch_<hex> for the highlighter, and the
-- palette swatches) are NOT here — they are created lazily at runtime from the literal colors and
-- flushed on ColorScheme, so they cannot live in a static factory. build() reads the LIVE palette;
-- init binds it via lvim-utils.highlight.bind so the accents track the theme.
--
---@module "lvim-color-picker.highlights"

local c = require("lvim-utils.colors")
local hl = require("lvim-utils.highlight")

local M = {}

--- The panel accents from the live palette (tint canon: each cell = its accent blended toward bg).
---@return table<string, table>
function M.build()
    return {
        -- (the slider tracks are painted per-cell at runtime with positional
        -- LvimColorPickerCell_<row>_<cell> groups, redefined in place each render, so no static
        -- track accents live here — see picker.lua cell_group)
        -- channel labels (R/G/B/H/S/L/…) — blue; the focused (active) row yellow. Value = yellow fg
        -- straight on the panel bg (no tint block).
        LvimColorPickerLabel = { fg = c.blue, bold = true },
        LvimColorPickerLabelActive = { fg = c.yellow, bold = true },
        LvimColorPickerValue = { fg = c.yellow, bold = true },
        -- [M]ode / [O]utput labels — GREEN
        LvimColorPickerColTitle = { fg = c.green, bold = true },
        -- mode/output chips: selected (active) vs idle — green (colour only on the chips)
        LvimColorPickerChipOn = { fg = c.bg, bg = c.green, bold = true },
        LvimColorPickerChipOff = { fg = c.fg_light, bg = hl.blend(c.green, c.bg, 0.2) },
    }
end

return M
